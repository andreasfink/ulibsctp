//
//  UMSCTPListener.m
//  ulibsctp
//
//  Created by Andreas Fink on 23.08.22.
//  Copyright © 2022 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSCTPListener.h"
#import "UMSocketSCTP.h"
#import "UMSocketSCTPReceivedPacket.h"
#import "UMLayerSctp.h"

#include <poll.h>

@implementation UMSCTPListener


- (UMSCTPListener *)init
{
    return [self initWithName:@"UMSCTPListener"];
}

- (UMSCTPListener *)initWithName:(NSString *)name;
{

    self = [super init];
    if(self)
    {
        self.name = name;
        _timeoutInMs = 3000; /* 3 sec */
    }
    return self;
}

- (void)backgroundInit
{
    ulib_set_thread_name(_name);
    NSLog(@"starting %@",_name);
}


- (void)backgroundExit
{
    NSString *s = [NSString stringWithFormat:@"%@ (terminating)",_name];
    ulib_set_thread_name(s);
    NSLog(@"terminating %@",s);
}

- (void)backgroundTask
{
   BOOL mustQuit = NO;
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
    UMSocketError returnValue = UMSocketError_no_error;
    
    if(_umsocket==NULL)
    {
        return UMSocketError_not_a_socket;
    }
    struct pollfd   pollfds[2];
    memset(pollfds, 0x00,sizeof(pollfds));
    pollfds[0].fd = _umsocket.fileDescriptor;
    pollfds[0].events = POLLIN | POLLPRI | POLLERR | POLLHUP | POLLNVAL;;

    if(_timeoutInMs < 100)
    {
        _timeoutInMs = 100;
    }
    int ret1 = poll(pollfds, 1, _timeoutInMs);
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
        /* we have some event to handle. */
        returnValue = UMSocketError_no_error;

        int revent = pollfds[0].revents;
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
        NSLog(@"handlePollResult:revent=%d %@",revent,[a componentsJoinedByString:@" | "]);
#endif
        int revent_error = UMSocketError_no_error;
        int revent_hup = 0;
        int revent_has_data = 0;
        int revent_invalid = 0;
        if(revent & POLLERR)
        {
            revent_error = [_umsocket getSocketError];
            if(     (revent_error != UMSocketError_no_error)
                &&  (revent_error != UMSocketError_no_data)
                &&  (revent_error !=UMSocketError_in_progress))
            {
                revent_hup = 1;
                [_eventDelegate processError:revent_error socket:_umsocket inArea:@"[UMSCTPListener waitAndHandleData]#1" layer:_layer];
            }
        }
        if(revent & POLLHUP)
        {
            revent_hup = 1;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"  revent_hup = 1");
#endif
            if(revent_error)
            [_eventDelegate processHangupOnSocket:_umsocket inArea:@"[UMSCTPListener waitAndHandleData]#2" layer:_layer];
        }
        if(revent & POLLNVAL)
        {
    revent_invalid = 1;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"  revent_invalid = 1");
#endif
            [_eventDelegate processInvalidValueOnSocket:_umsocket inArea:@"[UMSCTPListener waitAndHandleData]#3" layer:_layer];
        }
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
            if(_readDelegate)
            {
                rx = [_readDelegate receiveSCTP];
            }
            else
            {
                rx = [_umsocket receiveSCTP];
            }
            if((_layer) && (_dataDelegate==NULL))
            {
                [_layer processReceivedData:rx];
            }
            else
            {
                [_dataDelegate processReceivedData:rx];

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
            [_layer processHangUp];
        }
    }
    return returnValue;
}
@end
