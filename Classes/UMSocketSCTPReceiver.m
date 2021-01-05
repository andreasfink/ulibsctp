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
#import "UMSocketSCTPTCPListener.h"
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
        _tcpListeners   = [[NSMutableArray alloc]init];
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



typedef enum PollSocketType_enum
{
    POLL_SOCKET_TYPE_LISTENER_SCTP  = 0,
    POLL_SOCKET_TYPE_LISTENER_TCP   = 1,
    POLL_SOCKET_TYPE_OUTBOUND       = 2,
    POLL_SOCKET_TYPE_INBOUND        = 3,
    POLL_SOCKET_TYPE_OUTBOUND_TCP   = 4,
    POLL_SOCKET_TYPE_INBOUND_TCP    = 5,
} PollSocketType_enum;

- (UMSocketError) waitAndHandleData
{
    UMAssert(_registry!=NULL,@"_registry is NULL");

    UMSocketError returnValue = UMSocketError_generic_error;
    NSArray *listeners = [_registry allListeners];
    NSArray *tcp_listeners = [_registry allTcpListeners];
    NSArray *outbound_layers = [_registry allOutboundLayers];
    NSArray *inbound_layers = [_registry allInboundLayers];
    NSArray *outbound_tcp_layers = [_registry allOutboundTcpLayers];
    NSArray *inbound_tcp_layers = [_registry allInboundTcpLayers];
    NSUInteger listeners_count = listeners.count;
    NSUInteger tcp_listeners_count = _tcpListeners.count;
    NSUInteger outbound_count = outbound_layers.count;
    NSUInteger inbound_count = inbound_layers.count;
    NSUInteger outbound_tcp_count = outbound_tcp_layers.count;
    NSUInteger inbound_tcp_count = inbound_tcp_layers.count;
    
    NSUInteger listeners_count_valid = 0;
    NSUInteger tcp_listeners_count_valid = 0;
    NSUInteger outbound_count_valid = 0;
    NSUInteger inbound_count_valid = 0;
    NSUInteger outbound_tcp_count_valid = 0;
    NSUInteger inbound_tcp_count_valid = 0;

#if defined(ULIBSCTP_CONFIG_DEBUG)

    if(listeners==NULL)
    {
        NSLog(@"listeners=NULL");
    }
    if(tcp_listeners==NULL)
    {
        NSLog(@"tcp_listeners=NULL");
    }
    if(outbound_layers==NULL)
    {
        NSLog(@"outbound_layers=NULL");
    }
    if(inbound_layers==NULL)
    {
        NSLog(@"inbound_layers=NULL");
    }
    if(outbound_tcp_layers==NULL)
    {
        NSLog(@"outbound_tcp_layers=NULL");
    }
    if(inbound_tcp_layers==NULL)
    {
        NSLog(@"inbound_tcp_layers=NULL");
    }

    NSLog(@"listeners_count=%d",(int)listeners_count);
    NSLog(@"tcp_listeners_count=%d",(int)tcp_listeners_count);
    NSLog(@"outbound_count=%d",(int)outbound_count);
    NSLog(@"inbound_count=%d",(int)inbound_count);
    NSLog(@"outbound_tcp_count=%d",(int)outbound_tcp_count);
    NSLog(@"inbound_tcp_count=%d",(int)inbound_tcp_count);
#endif

    NSUInteger total_count = listeners_count + tcp_listeners_count + outbound_count + inbound_count + outbound_tcp_count + inbound_tcp_count;

    if(total_count == 0)
    {
        sleep(1);
        return UMSocketError_no_data;
    }

    struct pollfd *pollfds = calloc((total_count+1),sizeof(struct pollfd));
    NSAssert(pollfds !=0,@"can not allocate memory for poll()");

    memset(pollfds, 0x00,(total_count+1)  * sizeof(struct pollfd));
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
            
            listeners_count_valid++;
            pollfds[j].fd = listener.umsocket.fileDescriptor;
            pollfds[j].events = events;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d  (listener)",(int)j,(int)listener.umsocket.fileDescriptor);
#endif
            j++;
        }
    }
    for(NSUInteger i=0;i<tcp_listeners_count;i++)
    {
        UMSocketSCTPTCPListener *listener = tcp_listeners[i];
        if(listener.isInvalid==NO)
        {
            tcp_listeners_count_valid++;
            pollfds[j].fd = listener.umsocket.fileDescriptor;
            pollfds[j].events = events;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d  (listener-tcp)",(int)j,(int)listener.umsocket.fileDescriptor);
#endif
            j++;
        }
    }
    for(NSUInteger i=0;i<outbound_count;i++)
    {
        UMLayerSctp *layer = outbound_layers[i];
        if(layer.directSocket!=NULL)
        {
            outbound_count_valid++;
            pollfds[j].fd = layer.directSocket.fileDescriptor;
            pollfds[j].events = events;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d (outbound) assoc=%@",(int)j,(int)layer.directSocket.fileDescriptor,layer.directSocket.xassoc);
#endif
            j++;
        }
    }
    for(NSUInteger i=0;i<inbound_count;i++)
    {
        UMLayerSctp *layer = inbound_layers[i];
        if(layer.directSocket!=NULL)
        {
            inbound_count_valid++;
            pollfds[j].fd = layer.directSocket.fileDescriptor;
            pollfds[j].events = events;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d (inbound) assoc=%@",(int)j,(int)layer.directSocket.fileDescriptor,layer.directSocket.xassoc);
#endif
            j++;
        }
    }
    for(NSUInteger i=0;i<outbound_tcp_count;i++)
    {
        UMLayerSctp *layer = outbound_tcp_layers[i];
        if(layer.directTcpEncapsulatedSocket!=NULL)
        {
            outbound_tcp_count_valid++;
            pollfds[j].fd = layer.directTcpEncapsulatedSocket.fileDescriptor;
            pollfds[j].events = events;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d (outbound-tcp)",(int)j,(int)layer.directTcpEncapsulatedSocket.fileDescriptor);
#endif
            j++;
        }
    }
    for(NSUInteger i=0;i<inbound_tcp_count;i++)
    {
        UMLayerSctp *layer = inbound_tcp_layers[i];
        if(layer.directTcpEncapsulatedSocket!=NULL)
        {
            inbound_tcp_count_valid++;
            pollfds[j].fd = layer.directTcpEncapsulatedSocket.fileDescriptor;
            pollfds[j].events = events;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d (inbound-tcp)",(int)j,(int)layer.directTcpEncapsulatedSocket.fileDescriptor);
#endif
            j++;
        }
    }
    /* we could add a wakeup pipe here if we want. thats why the size of pollfds is +1 */
#if defined(ULIBSCTP_CONFIG_DEBUG)
    _timeoutInMs = 10000;
    NSLog(@"calling poll(timeout=%8.2fs)",((double)_timeoutInMs)/1000.0);
#endif

    NSAssert(_timeoutInMs > 100,@"UMSocketSCTP Receiver: _timeoutInMs is smaller than 100ms");

    total_count = j;
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
#if defined(ULIBSCTP_CONFIG_DEBUG)
    NSLog(@"listeners_count_valid=%d",(int)listeners_count_valid);
    NSLog(@"tcp_listeners_count_valid=%d",(int)tcp_listeners_count_valid);
    NSLog(@"outbound_count_valid=%d",(int)outbound_count_valid);
    NSLog(@"inbound_count_valid=%d",(int)inbound_count_valid);
    NSLog(@"outbound_tcp_count_valid=%d",(int)outbound_tcp_count_valid);
    NSLog(@"inbound_tcp_count_valid=%d",(int)inbound_tcp_count_valid);
#endif
        /* we have some event to handle. */
        returnValue = UMSocketError_no_error;

        UMSocketSCTPListener    *listener = NULL;
        UMLayerSctp             *outbound = NULL;
        UMLayerSctp             *inbound = NULL;
        UMSocketSCTP            *socket = NULL;
        UMSocket                *socketEncap = NULL;

        j = 0;
        for(NSUInteger i=0;i<listeners_count_valid;i++)
        {
            listener = listeners[j++];
            socket = listener.umsocket;
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:listener
                                               layer:NULL
                                              socket:socket
                                         socketEncap:NULL
                                           poll_time:poll_time
                                                type:POLL_SOCKET_TYPE_LISTENER_SCTP];
            if(r != UMSocketError_no_error)
            {
                returnValue= r;
            }
        }
        for(NSUInteger i=0;i<tcp_listeners_count_valid;i++)
        {
            listener = tcp_listeners[j++];
            socketEncap  = listener.umsocketEncapsulated;
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:listener
                                               layer:NULL
                                              socket:NULL
                                         socketEncap:socketEncap
                                           poll_time:poll_time
                                                type:POLL_SOCKET_TYPE_LISTENER_TCP];
            if(r != UMSocketError_no_error)
            {
                returnValue= r;
            }
        }
        for(NSUInteger i=0;i<outbound_count_valid;i++)
        {
            outbound = outbound_layers[j++];
            socket = outbound.directSocket;
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:NULL
                                               layer:outbound
                                              socket:socket
                                         socketEncap:NULL
                                           poll_time:poll_time
                                                type:POLL_SOCKET_TYPE_OUTBOUND];
            if(r != UMSocketError_no_error)
            {
                returnValue = r;
            }
        }
        for(NSUInteger i=0;i<inbound_count_valid;i++)
        {
            inbound = inbound_layers[j++];
            socket = inbound.directSocket;
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:NULL
                                               layer:inbound
                                              socket:socket
                                         socketEncap:NULL
                                           poll_time:poll_time
                                                type:POLL_SOCKET_TYPE_INBOUND];
            if(r != UMSocketError_no_error)
            {
                returnValue = r;
            }
        }
        for(NSUInteger i=0;i<outbound_tcp_count_valid;i++)
        {
            outbound = outbound_tcp_layers[j++];
            socketEncap  = outbound.directTcpEncapsulatedSocket;
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:NULL
                                               layer:outbound
                                              socket:NULL
                                         socketEncap:socketEncap
                                           poll_time:poll_time
                                                type:POLL_SOCKET_TYPE_OUTBOUND_TCP];
            if(r != UMSocketError_no_error)
            {
                returnValue = r;
            }
        }
        for(NSUInteger i=0;i<inbound_tcp_count_valid;i++)
        {
            inbound = inbound_tcp_layers[j++];
            socketEncap  = inbound.directTcpEncapsulatedSocket;
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:NULL
                                               layer:inbound
                                              socket:NULL
                                         socketEncap:socketEncap
                                           poll_time:poll_time
                                                type:POLL_SOCKET_TYPE_INBOUND_TCP];
            if(r != UMSocketError_no_error)
            {
                returnValue = r;
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
                             type:(PollSocketType_enum)type
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
        switch(type)
        {
            case POLL_SOCKET_TYPE_LISTENER_SCTP:
                rx = [socket receiveSCTP];
                break;
            case POLL_SOCKET_TYPE_LISTENER_TCP:
            {
                UMSocket *rs = (UMSocket *)socketEncap;
                rs = [rs accept:&returnValue];
                [rs switchToNonBlocking];
                [rs setIPDualStack];
                [rs setLinger];
                [rs setReuseAddr];
                rx = [self receiveEncapsulatedPacket:rs];
                if(rx.flags & SCTP_OVER_TCP_SETUP)
                {
                    NSString *session_key = [rx.data stringValue];
                    UMLayerSctp *session = [_registry layerForSessionKey:session_key];
                    if(session)
                    {
                        [_registry registerIncomingTcpLayer:session];
                    }
                }
            }
                break;
            case POLL_SOCKET_TYPE_OUTBOUND:
            case POLL_SOCKET_TYPE_INBOUND:
                rx = [socket receiveSCTP];
                break;
            case POLL_SOCKET_TYPE_OUTBOUND_TCP:
            case POLL_SOCKET_TYPE_INBOUND_TCP:
                rx = [self receiveEncapsulatedPacket:socketEncap];
                break;
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
