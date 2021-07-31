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

- (UMSocketSCTPReceiver *)initWithRegistry:(UMSocketSCTPRegistry *)r
{
    self = [super initWithName:@"UMSocketSCTPReceiver" workSleeper:NULL];
    if(self)
    {
        _outboundLayers = [[NSMutableArray alloc]init];
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
    NSArray *tcp_listeners = [_registry allTcpListeners];
    NSArray *outbound_layers = [_registry allOutboundLayers];
    NSArray *inbound_layers = [_registry allInboundLayers];
    NSArray *outbound_tcp_layers = [_registry allOutboundTcpLayers];
    NSArray *inbound_tcp_layers = [_registry allInboundTcpLayers];
    NSUInteger listeners_count = listeners.count;
    NSUInteger tcp_listeners_count = tcp_listeners.count;
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

    NSMutableArray *valid_listeners = [[NSMutableArray alloc]init];
    NSMutableArray *valid_tcp_listeners = [[NSMutableArray alloc]init];
    NSMutableArray *valid_outbound_layers = [[NSMutableArray alloc]init];
    NSMutableArray *valid_inbound_layers = [[NSMutableArray alloc]init];
    NSMutableArray *valid_outbound_tcp_layers = [[NSMutableArray alloc]init];
    NSMutableArray *valid_inbound_tcp_layers = [[NSMutableArray alloc]init];

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
            [valid_listeners addObject:listener];
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
        UMSocketSCTPListener *listener = tcp_listeners[i];
        if(listener.isInvalid==NO)
        {
            tcp_listeners_count_valid++;
            [valid_tcp_listeners addObject:listener];
            pollfds[j].fd = listener.umsocketEncapsulated.fileDescriptor;
            pollfds[j].events = events;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"pollfds[%d] = %d  (listener-tcp)",(int)j,(int)listener.umsocketEncapsulated.fileDescriptor);
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
            [valid_outbound_layers addObject:layer];
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
            [valid_inbound_layers addObject:layer];
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
            [valid_outbound_tcp_layers addObject:layer];
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
            [valid_inbound_tcp_layers addObject:layer];
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

    //total_count = j;
    int ret1 = poll(pollfds, j, _timeoutInMs);
    UMMicroSec poll_time = ulib_microsecondTime();
    if (ret1 < 0)
    {
        int eno = errno;
        if((eno==EINPROGRESS) || (eno == EINTR) || (eno==EAGAIN)  || (eno==EBUSY))
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
            listener = valid_listeners[i];
            socket = listener.umsocket;
            if(socket == NULL)
            {
                continue;
            }
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:listener
                                               layer:NULL
                                              socket:socket
                                         socketEncap:NULL
                                           poll_time:poll_time
                                                type:SCTP_SOCKET_TYPE_LISTENER_SCTP];
            if(r != UMSocketError_no_error)
            {
                returnValue= r;
            }
            j++;
        }
        for(NSUInteger i=0;i<tcp_listeners_count_valid;i++)
        {
            listener = valid_tcp_listeners[i];
            socketEncap  = listener.umsocketEncapsulated;
            if(socketEncap == NULL)
            {
                continue;
            }
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:listener
                                               layer:NULL
                                              socket:NULL
                                         socketEncap:socketEncap
                                           poll_time:poll_time
                                                type:SCTP_SOCKET_TYPE_LISTENER_TCP];
            if(r != UMSocketError_no_error)
            {
                returnValue= r;
            }
            j++;
        }
        for(NSUInteger i=0;i<outbound_count_valid;i++)
        {
            outbound = valid_outbound_layers[i];
            socket = outbound.directSocket;
            if(socket == NULL)
            {
                continue;
            }
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:NULL
                                               layer:outbound
                                              socket:socket
                                         socketEncap:NULL
                                           poll_time:poll_time
                                                type:SCTP_SOCKET_TYPE_OUTBOUND];
            if(r != UMSocketError_no_error)
            {
                returnValue = r;
            }
            j++;
        }
        for(NSUInteger i=0;i<inbound_count_valid;i++)
        {
            inbound = valid_inbound_layers[i];
            socket = inbound.directSocket;
            if(socket == NULL)
            {
                continue;
            }
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:NULL
                                               layer:inbound
                                              socket:socket
                                         socketEncap:NULL
                                           poll_time:poll_time
                                                type:SCTP_SOCKET_TYPE_INBOUND];
            if(r != UMSocketError_no_error)
            {
                returnValue = r;
            }
            j++;
        }
        for(NSUInteger i=0;i<outbound_tcp_count_valid;i++)
        {
            outbound = valid_outbound_tcp_layers[i];
            socketEncap  = outbound.directTcpEncapsulatedSocket;
            if(socketEncap == NULL)
            {
                continue;
            }
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:NULL
                                               layer:outbound
                                              socket:NULL
                                         socketEncap:socketEncap
                                           poll_time:poll_time
                                                type:SCTP_SOCKET_TYPE_OUTBOUND_TCP];
            if(r != UMSocketError_no_error)
            {
                returnValue = r;
            }
            j++;
        }
        for(NSUInteger i=0;i<inbound_tcp_count_valid;i++)
        {
            inbound = valid_inbound_tcp_layers[i];
            socketEncap  = inbound.directTcpEncapsulatedSocket;
            if(socketEncap == NULL)
            {
                continue;
            }
            int revent = pollfds[j].revents;
            UMSocketError r = [self handlePollResult:revent
                                            listener:NULL
                                               layer:inbound
                                              socket:NULL
                                         socketEncap:socketEncap
                                           poll_time:poll_time
                                                type:SCTP_SOCKET_TYPE_INBOUND_TCP];
            if(r != UMSocketError_no_error)
            {
                returnValue = r;
            }
            j++;
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
                             type:(SCTP_SocketType_enum)type
{
    
    if(socket == NULL)
    {
        return UMSocketError_not_a_socket;
    }

#if defined(ULIBSCTP_CONFIG_DEBUG)
    
    NSMutableArray *a = [[NSMutableArray alloc]init];
    if(revent & POLLIN)
    {
        [a addObject:@"POLLIN"];
    }
    if(revent & POLLPRI)
    {
        [a addObject:@"POLLPRI"];
    }
    if(revent & POLLOUT)
    {
        [a addObject:@"POLLOUT"];
    }
    if(revent & POLLRDNORM)
    {
        [a addObject:@"POLLRDNORM"];
    }
    if(revent & POLLRDBAND)
    {
        [a addObject:@"POLLRDBAND"];
    }
    if(revent & POLLWRBAND)
    {
        [a addObject:@"POLLWRBAND"];
    }
    if(revent & POLLERR)
    {
        [a addObject:@"POLLERR"];
    }
    if(revent & POLLHUP)
    {
        [a addObject:@"POLLHUP"];
    }
    if(revent & POLLNVAL)
    {
        [a addObject:@"POLLNVAL"];
    }

    NSLog(@"- (UMSocketError)handlePollResult:revent=%d %@",revent,[a componentsJoinedByString:@" | "]);
    NSLog(@"                         listener:%@",listener ? listener.description : @"NULL");
    NSLog(@"                            layer:%@",layer ? layer.layerName : @"NULL");
    NSLog(@"                           socket:%@", socket ? socket.description : @"NULL");
    NSLog(@"                      socketEncap:%@", socketEncap ? socketEncap.description : @"NULL");
    NSLog(@"                        poll_time:%lld",poll_time);
    switch(type)
    {
        case SCTP_SOCKET_TYPE_LISTENER_SCTP:
            NSLog(@"                             type:SCTP_SOCKET_TYPE_LISTENER_SCTP");
            break;
        case SCTP_SOCKET_TYPE_LISTENER_TCP:
            NSLog(@"                             type:SCTP_SOCKET_TYPE_LISTENER_TCP");
            break;
        case SCTP_SOCKET_TYPE_OUTBOUND:
            NSLog(@"                             type:SCTP_SOCKET_TYPE_OUTBOUND");
            break;
        case SCTP_SOCKET_TYPE_INBOUND:
            NSLog(@"                             type:SCTP_SOCKET_TYPE_INBOUND");
            break;
        case SCTP_SOCKET_TYPE_OUTBOUND_TCP:
            NSLog(@"                             type:SCTP_SOCKET_TYPE_OUTBOUND_TCP");
            break;
        case SCTP_SOCKET_TYPE_INBOUND_TCP:
            NSLog(@"                             type:SCTP_SOCKET_TYPE_INBOUND_TCP");
            break;

    }
#endif
    
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
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  Error: %@",[UMSocket getSocketErrorString:revent_error]);
#endif
        [layer processError:revent_error];
        [listener processError:revent_error];
    }
    if(revent & POLLHUP)
    {
        revent_hup = 1;
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  revent_hup = 1");
#endif

    }
#ifdef POLLRDHUP
    if(revent & POLLRDHUP)
    {
        revent_hup = 1;
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  revent_hup = 1");
#endif
    }
#endif
    if(revent & POLLNVAL)
    {
        revent_invalid = 1;
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  revent_invalid = 1");
#endif

    }
#ifdef POLLRDBAND
        if(revent & POLLRDBAND)
        {
            revent_has_data = 1;
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  revent_has_data = 1");
#endif

        }
#endif
    if(revent & (POLLIN | POLLPRI))
    {
        revent_has_data = 1;
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  revent_has_data = 1");
#endif
    }
    if(revent_has_data)
    {
        UMSocketSCTPReceivedPacket *rx = NULL;
        
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  receiving packet");
#endif

        switch(type)
        {
            case SCTP_SOCKET_TYPE_LISTENER_SCTP:
                UMAssert(socket != NULL, @"socket can not be null here");
                rx = [socket receiveSCTP];
                [listener processReceivedData:rx];
                break;
            case SCTP_SOCKET_TYPE_LISTENER_TCP:
            {
                UMAssert(socketEncap != NULL, @"socketEncap can not be null here");
                UMSocket *rs = socketEncap;
                rs = [rs accept:&returnValue];
                [rs switchToNonBlocking];
                [rs setIPDualStack];
                [rs setLinger];
                [rs setReuseAddr];
                UMSocketError err = UMSocketError_not_known;
                rx = [self receiveEncapsulatedPacket:rs error:&err timeout:2.0];/* potential DDOS / busyloop */
                BOOL success = NO;

#if defined(ULIBSCTP_CONFIG_DEBUG)
                if(rx==NULL)
                {
                    NSLog(@"Received SCTP over TCP packet: rx=null err=%d %@",err,[UMSocket getSocketErrorString:err]);
                }
                else
                {
                    if (err == UMSocketError_no_error)
                    {
                        NSString *s = [rx description];
                        NSLog(@"Received SCTP over TCP packet: %@",s);
                    }
                    else
                    {
                        NSString *s = [rx description];
                        NSLog(@"Received SCTP over TCP packet with error %d %@: %@",err,[UMSocket getSocketErrorString:err],s);
                    }
                }

#endif
                if(rx.tcp_flags & SCTP_OVER_TCP_SETUP)
                {
                    NSString *session_key = [rx.data stringValue];
                    UMLayerSctp *session = [_registry layerForSessionKey:session_key];
                    if(session)
                    {
#if defined(ULIBSCTP_CONFIG_DEBUG)
                        NSLog(@"layer found with session key %@",session_key);
#endif
                        session.directTcpEncapsulatedSocket = rs;
                        [_registry registerIncomingTcpLayer:session];
                        [session handleLinkUpTcpEcnap];
                        success = YES;
                        
                        UMSocketError err2 = UMSocketError_no_error;
                        uint32_t tmp_assocId;
                        [session sendEncapsulated:rx.data
                                            assoc:&tmp_assocId
                                           stream:0
                                         protocol:0
                                            error:&err2
                                            flags:SCTP_OVER_TCP_SETUP_CONFIRM | SCTP_OVER_TCP_NOTIFICATION];
                        session.status = UMSOCKET_STATUS_IS;
                        [session reportStatus];
                    }
                    else
                    {
#if defined(ULIBSCTP_CONFIG_DEBUG)
                        NSLog(@"No session with session key %@ found",session_key);
#endif
                    }
                }
                [rs switchToNonBlocking];
                if(success==NO)
                {
                    [rs close];
                    rs = NULL;
                }
            }
                break;
            case SCTP_SOCKET_TYPE_OUTBOUND:
            case SCTP_SOCKET_TYPE_INBOUND:
            {
#if defined(ULIBSCTP_CONFIG_DEBUG)
                NSLog(@"  calling receiveSCTP");
#endif
                rx = [socket receiveSCTP];
                [layer processReceivedData:rx];
                break;
            }
            case SCTP_SOCKET_TYPE_OUTBOUND_TCP:
            case SCTP_SOCKET_TYPE_INBOUND_TCP:
            {
#if defined(ULIBSCTP_CONFIG_DEBUG)
                NSLog(@"  calling receiveEncapsulatedPacket");
#endif
                UMSocketError err = UMSocketError_no_error;
                rx = [self receiveEncapsulatedPacket:socketEncap error:&err timeout:0.05];
                if((err != UMSocketError_has_data) && (err!=UMSocketError_try_again) && (err != UMSocketError_no_error))
                {
                    revent_hup = 1;
                }
#if defined(ULIBSCTP_CONFIG_DEBUG)
                if(rx==NULL)
                {
                    NSLog(@"Received SCTP over TCP packet: sock=%d rx=null err=%d %@",socketEncap.sock,err,[UMSocket getSocketErrorString:err]);
                }
                else
                {
                    if ((err == UMSocketError_no_error) || (err==UMSocketError_has_data) || (err==UMSocketError_has_data_and_hup))
                    {
                        NSString *s = [rx description];
                        NSLog(@"Received SCTP over TCP packet: %@",s);
                    }
                    else
                    {
                        NSString *s = [rx description];
                        NSLog(@"Received SCTP over TCP packet with sock=%d error %d %@: %@",socketEncap.sock,err,[UMSocket getSocketErrorString:err],s);
                    }
                }

#endif
                if(rx)
                {
                    [layer processReceivedData:rx];
                    rx = NULL;
                }
                break;
            }
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
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  calling processHangUp");

#endif
        [layer processHangUp];
        [listener processHangUp];
        if(layer!=NULL)
        {
           if(type==SCTP_SOCKET_TYPE_OUTBOUND_TCP)
           {
               [_registry unregisterOutgoingTcpLayer:layer];
           }
           else if(type==SCTP_SOCKET_TYPE_INBOUND_TCP)
           {
               [_registry unregisterIncomingTcpLayer:layer];
           }
        }
    }
    if(revent_invalid)
    {
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"  calling processInvalidSocket");

#endif
        [layer processInvalidSocket];
        [listener processInvalidSocket];
    }
    return returnValue;
}


-(UMSocketSCTPReceivedPacket *)receiveEncapsulatedPacket:(UMSocket *)umsocket
                                                   error:(UMSocketError *)errptr
                                                 timeout:(NSTimeInterval)timeout
{
    UMSocketSCTPReceivedPacket *rx = NULL;
    NSDate *start = [NSDate date];
    NSTimeInterval timeElapsed = 0;
    UMSocketError err = UMSocketError_no_data;
    while((timeElapsed<timeout) && (rx==NULL) && ((err==UMSocketError_no_data) || (err==UMSocketError_try_again)))
    {
        rx = [self receiveEncapsulatedPacket:umsocket error:&err];
        if(errptr)
        {
            *errptr = err;
        }
        timeElapsed = [[NSDate date]timeIntervalSinceDate:start];
        if((rx==NULL) && ((err==UMSocketError_no_data) || (err==UMSocketError_try_again)))
        {
            usleep(10000); /* to avoid deadlocks */
        }
    }
#if defined (ULIBSCTP_CONFIG_DEBUG)
    NSLog(@"receiveEncapsulatedPacket returns error=%@ on socket %d with rx=%@",[UMSocket getSocketErrorString:err],umsocket.sock,rx.description);
#endif
    if(errptr)
    {
        *errptr = err;
    }
    return rx;
}

-(UMSocketSCTPReceivedPacket *)receiveEncapsulatedPacket:(UMSocket *)umsocket error:(UMSocketError *)errptr
{
    UMSocketError err =  [umsocket receiveToBufferWithBufferLimit:sizeof(sctp_over_tcp_header)];
    if(err==UMSocketError_has_data_and_hup)
    {
        err = UMSocketError_has_data;
    }
    if(err)
    {
        if(errptr)
        {
            *errptr = err;
        }
        if(err!=UMSocketError_has_data)
        {
            return NULL;
        }
    }
    NSData *receivedData = NULL;
    sctp_over_tcp_header header;
    UMSocketSCTPReceivedPacket *rx = NULL;
    [umsocket.dataLock lock];
    
    if(errptr)
    {
        *errptr = UMSocketError_no_data;
    }
    if(umsocket.receiveBuffer.length >= sizeof(sctp_over_tcp_header))
    {
        memcpy(&header,umsocket.receiveBuffer.bytes,sizeof(header));
        header.header_length = ntohl(header.header_length);
        header.payload_length = ntohl(header.payload_length);
        header.protocolId = ntohl(header.protocolId);
        header.streamId = ntohs(header.streamId);
        header.flags = ntohs(header.flags);
        
        if(header.header_length != sizeof(header))
        {
            if(errptr)
            {
                *errptr = UMSocketError_connection_aborted;
            }
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"- header-length-mismatch");
#endif
            return NULL;
        }
        else
        {
            rx = [[UMSocketSCTPReceivedPacket alloc]init];
            rx.streamId = header.streamId;
            rx.protocolId = header.protocolId;
            rx.context = 0;
            rx.data = receivedData;
            rx.remoteAddress = umsocket.connectedRemoteAddress;
            rx.remotePort  = umsocket.connectedRemotePort;
            rx.localAddress = umsocket.connectedLocalAddress;
            rx.localPort  = umsocket.connectedLocalPort;
            rx.tcp_flags = header.flags;
            rx.isNotification = NO;
            if(header.payload_length > 0)
            {
                UMSocketError err =  [umsocket receiveToBufferWithBufferLimit:sizeof(sctp_over_tcp_header)+header.payload_length];
                if(err)
                {
                    if(errptr)
                    {
                        *errptr = err;
                        rx = NULL;
                    }
                }
                else
                {
                    if(umsocket.receiveBuffer.length >= sizeof(sctp_over_tcp_header) + header.payload_length)
                    {
                        const void *start = umsocket.receiveBuffer.bytes;
                        start += header.header_length;
                        receivedData = [NSData dataWithBytes:start length:header.payload_length];
                        rx.data = receivedData;
                        /* remove the packet data */
                        [umsocket.receiveBuffer replaceBytesInRange:NSMakeRange(0, sizeof(sctp_over_tcp_header) + header.payload_length)
                                                          withBytes:nil
                                                             length:0];

                        if(errptr)
                        {
                            *errptr = UMSocketError_no_error;
                        }
                    }
                    else
                    {
                        /* we have a valid header but not enough data yet */
                        rx = NULL;
                        if(errptr)
                        {
                            *errptr = UMSocketError_try_again;
#if defined(ULIBSCTP_CONFIG_DEBUG)
                            NSLog(@"- header ok but not enough data yet. waiting for %lu additional bytes",(unsigned long)header.payload_length);
#endif
                        }
                    }
                }
            }
            else
            {
                if(errptr)
                {
                    *errptr = UMSocketError_no_error;
                }
            }
        }
    }
    else
    {
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"- not enough data");
#endif
    }
    [umsocket.dataLock unlock];
    return rx;
}

@end
