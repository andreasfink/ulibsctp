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

#include <poll.h>
@implementation UMSocketSCTPReceiver

- (UMSocketSCTPReceiver *)initWithRegistry:(UMSocketSCTPRegistry *)r;
{
    self = [super init];
    if(self)
    {
        _outboundLayers = [[NSMutableArray alloc]init];
        _listeners = [[NSMutableArray alloc]init];
        _lock = [[UMMutex alloc]init];
        _timeoutInMs = 4000;
        _registry = r;
    }
    return self;
}

- (void)backgroundInit
{
    ulib_set_thread_name(@"UMSocketSCTPReceiver");
}

- (void)backgroundExit
{
    ulib_set_thread_name(@"UMSocketSCTPReceiver (terminating)");
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
    [control_sleeper wakeUp:UMSleeper_StartupCompletedSignal];
    
    [self backgroundInit];


    while((UMBackgrounder_running == self.runningStatus) && (mustQuit==NO))
    {
        [self waitAndHandleData];
    }
    [self backgroundExit];
    self.runningStatus = UMBackgrounder_notRunning;
    self.workSleeper = NULL;
    [control_sleeper wakeUp:UMSleeper_ShutdownCompletedSignal];
}

- (UMSocketError) waitAndHandleData
{
    
    UMSocketError returnValue = UMSocketError_generic_error;
    
    [_lock lock];
    //NSArray *outboundLayers = [_registry allOutboundLayers];
    NSArray *listeners = [_registry allListeners];
    NSUInteger listeners_count = listeners.count;

    [_lock unlock];

    struct pollfd *pollfds = calloc(listeners_count+1,sizeof(struct pollfd));
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
        pollfds[j].fd = listener.umsocket.fileDescriptor;
        pollfds[j].events = events;
        j++;
    }
    /* we could add a wakeup pipe here if we want */
//#if (ULIBSCTP_CONFIG==Debug)
//    NSLog(@"calling poll(timeout=%8.2fs)",((double)_timeoutInMs)/1000.0);
//#endif

    int ret1 = poll(pollfds, j, _timeoutInMs);
//#if (ULIBSCTP_CONFIG==Debug)
//    NSLog(@"poll returns: %d %s",errno,strerror(errno));
//#endif

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

//        UMLayerSctp *outbound = NULL;
        UMSocketSCTPListener *listener = NULL;
        UMSocketSCTP *socket = NULL;
        for(int i=0;i<j;i++)
        {
            listener = listeners[i];
            socket = listener.umsocket;

            int revent = pollfds[i].revents;
            int revent_error = UMSocketError_no_error;
            int revent_hup = 0;
            int revent_has_data = 0;
            int revent_invalid = 0;
            
            if(revent & POLLERR)
            {
                revent_error = [socket getSocketError];
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
                UMSocketSCTPReceivedPacket *rx = [socket receiveSCTP];
                [listener processReceivedData:rx];
            }
            if(revent_hup)
            {
                [listener processHangUp];
            }
            if(revent_invalid)
            {
                [listener processInvalidSocket];
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
            sleep(1);
            break;
    }
    return returnValue;
}

@end
