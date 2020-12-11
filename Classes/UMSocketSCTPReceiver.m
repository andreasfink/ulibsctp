//
//  UMSocketSCTPReceiver.m
//  ulibsctp
//
//  Created by Andreas Fink on 18.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPReceiver.h"
#import "UMLayerSctp.h"
#import "UMSocketSCTP.h"
#import "UMSocketSCTPListener.h"
#import "UMSocketSCTPRegistry.h"
#import "UMSctpOverTcp.h"

#include <poll.h>
@implementation UMSocketSCTPReceiver

- (UMSocketSCTPReceiver *)init
{
    NSAssert(0, @"use [UMSocketSCTPReceiver initWithRegistry:]");
    return NULL;
}

- (UMSocketSCTPReceiver *)initWithRegistry:(UMSocketSCTPRegistry *)r;
{
    self = [super initWithName:@"UMSocketSCTPReceiver" workSleeper:NULL];
    if(self)
    {
        _outboundLayers = [[NSMutableArray alloc]init];
        _listeners      = [[NSMutableArray alloc]init];
        //_lock           = [[UMMutex alloc]initWithName:@"socket-sctp-receiver-lock"];
        _timeoutInMs    = 5000;
        _registry       = r;
    }
    return self;
}

- (void)backgroundInit
{
    ulib_set_thread_name(@"UMSocketSCTPReceiver");
	NSLog(@"starting UMSocketSCTPReceiver");
}


- (void)backgroundExit
{
    ulib_set_thread_name(@"UMSocketSCTPReceiver (terminating)");
	NSLog(@"terminating UMSocketSCTPReceiver");
}

- (void)backgroundTask
{
    BOOL mustQuit = NO;
    if(self.name)
    {
        ulib_set_thread_name(self.name);
    }
    if(self.runningStatus != UMBackgrounder_startingUp)
    {
        return;
    }
    if(self.workSleeper==NULL)
    {
        self.workSleeper = [[UMSleeper alloc]initFromFile:__FILE__ line:__LINE__ function:__func__];
        [self.workSleeper prepare];
    }
    self.runningStatus = UMBackgrounder_running;
    [self.control_sleeper wakeUp:UMSleeper_StartupCompletedSignal];
    
    [self backgroundInit];

    while((UMBackgrounder_running == self.runningStatus) && (mustQuit==NO))
    {
        [self waitAndHandleData];
    }
    [self backgroundExit];
    self.runningStatus = UMBackgrounder_notRunning;
    self.workSleeper = NULL;
    [self.control_sleeper wakeUp:UMSleeper_ShutdownCompletedSignal];
}



- (UMSocketError) waitAndHandleData
{
    UMAssert(_registry!=NULL,@"_registry is NULL");

    UMSocketError returnValue = UMSocketError_generic_error;
    NSArray *listeners = [_registry allListeners];
    NSArray *outbound_layers = [_registry allOutboundLayers];
    NSUInteger listeners_count = listeners.count;
    NSUInteger outbound_count = outbound_layers.count;
    if((listeners_count == 0) && (outbound_count==0))
    {
        sleep(1);
        return UMSocketError_no_data;
    }

    struct pollfd *pollfds = calloc(listeners_count+outbound_count+1,sizeof(struct pollfd));
    NSAssert(pollfds !=0,@"can not allocate memory for poll()");

    memset(pollfds, 0x00,listeners_count+1  * sizeof(struct pollfd));
    int events = POLLIN | POLLPRI | POLLERR | POLLHUP | POLLNVAL;
#ifdef POLLRDBAND
    events |= POLLRDBAND;
#endif
    
#ifdef POLLRDHUP
    events |= POLLRDHUP;
#endif
    nfds_t j=0;

    for(NSUInteger i=0;i<listeners_count;i++)
    {
        UMSocketSCTPListener *listener = listeners[i];
        if(listener.isInvalid==NO)
        {
            pollfds[j].fd = listener.umsocket.fileDescriptor;
            pollfds[j].events = events;
            j++;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d  (listener)",(int)j,(int)listener.umsocket.fileDescriptor);
#endif
        }
    }
    for(NSUInteger i=0;i<outbound_count;i++)
    {
        UMLayerSctp *layer = outbound_layers[i];
        if(layer.directSocket!=NULL)
        {
            pollfds[j].fd = layer.directSocket.fileDescriptor;
            pollfds[j].events = events;
            j++;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d (direct) assoc=%@",(int)j,(int)layer.directSocket.fileDescriptor,layer.directSocket.xassoc);
#endif
        }
    }
    /* we could add a wakeup pipe here if we want. thats why the size of pollfds is +1 */
#if defined(ULIBSCTP_CONFIG_DEBUG)
    NSLog(@"calling poll(timeout=%8.2fs)",((double)_timeoutInMs)/1000.0);
#endif

    NSAssert(_timeoutInMs > 100,@"UMSocketSCTP Receiver: _timeoutInMs is smaller than 100ms");

    int ret1 = poll(pollfds, j, _timeoutInMs);

    UMMicroSec poll_time = ulib_microsecondTime();

    if (ret1 < 0)
    {
        int eno = errno;
        if((eno==EINPROGRESS) || (eno == EINTR) || (eno==EAGAIN))
        {
            returnValue = UMSocketError_no_data;
        }
        else
        {
            returnValue = [UMSocket umerrFromErrno:eno];
        }
    }
    else if (ret1 == 0)
    {
        returnValue = UMSocketError_no_data;
    }
    else /* ret1 > 0 */
    {
        /* we have some event to handle. */
        returnValue = UMSocketError_no_error;

        UMLayerSctp             *outbound = NULL;
        UMSocketSCTPListener    *listener = NULL;
        UMSocketSCTP            *socket = NULL;
        UMSocket                *socketEncap = NULL;

        j = 0;
        for(NSUInteger i=0;i<listeners_count;i++)
        {
            listener = listeners[i];
            if(listener.isInvalid==NO)
            {
                socket = listener.umsocket;
                socketEncap  = listener.umsocketEncapsulated;
                int revent = pollfds[j].revents;
                UMSocketError r = [self handlePollResult:revent
												listener:listener
												   layer:NULL
                                                  socket:socket
                                             socketEncap:socketEncap
											   poll_time:poll_time];
                if(r != UMSocketError_no_error)
                {
                    returnValue= r;
                }
                j++;
            }
        }
        for(NSUInteger i=0;i<outbound_count;i++)
        {
            outbound = outbound_layers[i];
            if(outbound.directSocket!=NULL)
            {
                socket = outbound.directSocket;
                socketEncap  = outbound.directTcpEncapsulatedSocket;
                int revent = pollfds[j].revents;
                UMSocketError r = [self handlePollResult:revent
												listener:NULL
												   layer:outbound
												  socket:socket
                                             socketEncap:socketEncap
											   poll_time:poll_time];
                if(r != UMSocketError_no_error)
                {
                    returnValue = r;
                }
                j++;
            }
        }
    }
    switch(returnValue)
    {
        case UMSocketError_has_data_and_hup:
        case UMSocketError_has_data:
        case UMSocketError_no_error:
        case UMSocketError_no_data:
        case UMSocketError_timed_out:
            break;
        default:
            /* if poll returns an error, we will not have hit the timeout. Hence we risk a busy loop */
            usleep(100000); /* sleep 0.1 sec */
            break;
    }

    if(pollfds)
    {
        free(pollfds);
        pollfds=NULL;
    }
    return returnValue;
}

- (UMSocketError)handlePollResult:(int)revent
						 listener:(UMSocketSCTPListener *)listener
							layer:(UMLayerSctp *)layer
                           socket:(UMSocketSCTP *)socket
                      socketEncap:(UMSocket *)socketEncap
						poll_time:(UMMicroSec)poll_time
{
	if((listener==NULL) && (layer==NULL))
	{
		UMAssert(0,@"Either listener or layer have to be set");
	}
	if((listener!=NULL) && (layer!=NULL))
	{
		UMAssert(0,@"Either listener or layer have to be set but not both");
	}

    UMSocketError returnValue = UMSocketError_no_error;

    int revent_error = UMSocketError_no_error;
    int revent_hup = 0;
    int revent_has_data = 0;
    int revent_invalid = 0;
    if(revent & POLLERR)
    {
        if(socket)
        {
            revent_error = [socket getSocketError];
        }
        else
        {
            revent_error = [socketEncap getSocketError];
        }
        [layer processError:revent_error];
        [listener processError:revent_error];
    }
    if(revent & POLLHUP)
    {
        revent_hup = 1;
    }
#ifdef POLLRDHUP
    if(revent & POLLRDHUP)
    {
        revent_hup = 1;
    }
#endif
    if(revent & POLLNVAL)
    {
        revent_invalid = 1;
    }
#ifdef POLLRDBAND
        if(revent & POLLRDBAND)
        {
            revent_has_data = 1;
        }
#endif
    if(revent & (POLLIN | POLLPRI))
    {
        revent_has_data = 1;
    }
    if(revent_has_data)
    {
        UMSocketSCTPReceivedPacket *rx;
        if(socket)
        {
            rx = [socket receiveSCTP];
        }
        else
        {
            [self receiveEncapsulatedPacket:socketEncap];
        }
        if(rx.data.length > 0)
        {
            rx.rx_time = ulib_microsecondTime();
            rx.poll_time = poll_time;
            [layer processReceivedData:rx];
            [listener processReceivedData:rx];
            rx.process_time = ulib_microsecondTime();
        }
        if(revent_hup)
        {
            returnValue = UMSocketError_has_data_and_hup;
        }
        else
        {
            returnValue = UMSocketError_has_data;
        }
    }
    if(revent_hup)
    {
        [layer processHangUp];
        [listener processHangUp];
    }
    if(revent_invalid)
    {
        [layer processInvalidSocket];
        [listener processInvalidSocket];
    }
    return returnValue;
}

-(UMSocketSCTPReceivedPacket *)receiveEncapsulatedPacket:(UMSocket *)umsocket
{
    BOOL protocolViolation = NO;
    NSData *receivedData = NULL;
    sctp_over_tcp_header header;
    UMSocketSCTPReceivedPacket *rx = NULL;
    [umsocket.dataLock lock];
    if(umsocket.receiveBuffer.length > sizeof(sctp_over_tcp_header))
    {
        memcpy(&header,umsocket.receiveBuffer.bytes,sizeof(header));
        header.header_length = ntohl(header.header_length);
        header.payload_length = ntohl(header.payload_length);
        header.protocolId = ntohl(header.protocolId);
        header.streamId = ntohs(header.streamId);
        header.flags = ntohs(header.flags);
        if(header.header_length != sizeof(header))
        {
            protocolViolation = YES;
        }
        else
        {
            if(header.payload_length > 0)
            {
                if(umsocket.receiveBuffer.length > sizeof(sctp_over_tcp_header) + header.payload_length)
                {
                    const void *start = umsocket.receiveBuffer.bytes;
                    start += header.header_length;
                    receivedData = [NSData dataWithBytes:start length:header.payload_length];
                    rx = [[UMSocketSCTPReceivedPacket alloc]init];
                    rx.streamId = header.streamId;
                    rx.protocolId = header.protocolId;
                    rx.context = 0;
                    rx.data = receivedData;
                    rx.remoteAddress = umsocket.connectedRemoteAddress;
                    rx.remotePort  = umsocket.connectedRemotePort;
                    rx.localAddress = umsocket.connectedLocalAddress;
                    rx.localPort  = umsocket.connectedLocalPort;
                    rx.flags = header.flags;
                    rx.isNotification = NO;
                }
            }
        }
    }
    [umsocket.dataLock unlock];
    return rx;
}

@end
