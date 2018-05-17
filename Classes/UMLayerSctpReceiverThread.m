//
//  UMLayerSctpReceiverThread.m
//  ulibsctp
//
//  Created by Andreas Fink on 01/12/14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMLayerSctpReceiverThread.h"
#import "UMLayerSctp.h"

@implementation UMLayerSctpReceiverThread


-(UMLayerSctpReceiverThread *)initWithSctpLink:(UMLayerSctp *)lnk
{
    self = [super init];
    if(self)
    {
        link = lnk;
        control_sleeper = [[UMSleeper alloc]initFromFile:__FILE__
                                                    line:__LINE__
                                                function:__func__];
        [control_sleeper prepare];
    }
    return self;
}

- (void)backgroundInit
{
    NSString *s = [NSString stringWithFormat:@"sctp receiverThread %@",link.layerName];
    ulib_set_thread_name(s);
    [link logDebug:@"background receiver started"];
    [link logDebug:s];
}

- (void)backgroundExit
{
    NSString *s = [NSString stringWithFormat:@"sctp receiverThread (terminating) %@",link.layerName];
    ulib_set_thread_name(s);
    [link logDebug:s];
}


- (void)backgroundTask
{
    BOOL mustQuit = NO;
    UMSocketError e;

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
    
    sleep(1);
    /* we sleep here for a second to give connectx a chance to establish */
    if(enableLogging)
    {
        NSLog(@"%@: started up successfully",self.name);
    }
    [self backgroundInit];
    while((UMBackgrounder_running == self.runningStatus) && (mustQuit==NO))
    {
        int hasData = 0;
        int hasHup = 0;
        e = [link dataIsAvailableSCTP:&hasData
                               hangup:&hasHup];
#if  (ULIBSCTP_CONFIG==Debug)
        NSLog(@"[link dataIsAvailableSCTP] returns %d",e);
#endif

        if((e==UMSocketError_has_data)
           || (e==UMSocketError_has_data_and_hup)
           || (hasData))
        {
            [link receiveData];
        }
        if((hasHup) || (e==UMSocketError_has_data_and_hup))
        {
            mustQuit = YES;
        }

        switch(e)
        {
            case UMSocketError_no_error:
            case UMSocketError_no_data:
            case UMSocketError_try_again:
            case UMSocketError_in_progress:
            case UMSocketError_has_data:
            case UMSocketError_has_data_and_hup:
                break;
            case UMSocketError_file_descriptor_not_open:
                [link logMinorError:@"link dataIsAvailable returns 'file_descriptor_not_open'"];
                mustQuit=YES;
                break;

            default:
            {
                NSString *s = [NSString stringWithFormat:@"link dataIsAvailable returns error %d %@",e, [UMSocket getSocketErrorString:e]];
                [link logMinorError:s];
                mustQuit=YES;
                break;
            }
        }
    }
    if(enableLogging)
    {
        NSLog(@"%@: shutting down",self.name);
    }
    [self backgroundExit];
    self.runningStatus = UMBackgrounder_notRunning;
    self.workSleeper = NULL;
    [control_sleeper wakeUp:UMSleeper_ShutdownCompletedSignal];
}
@end
