//
//  UMLayerSctpReceiverThread.m
//  ulibsctp
//
//  Created by Andreas Fink on 01/12/14.
//  Copyright (c) 2016 Andreas Fink
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
        control_sleeper = [[UMSleeper alloc]init];
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

- (int)backgroundTaskOld
{
    UMSocketError e = UMSocketError_no_error;
    int count = 0;

    e = [link dataIsAvailable];
    if((e==UMSocketError_has_data) || (e==UMSocketError_has_data_and_hup))
    {
        count = [link receiveData];
    }
    else
    {
        count = 0;
    }
    if(e == UMSocketError_has_data)
    {
        return count;
    }
    else if(e==UMSocketError_has_data_and_hup)
    {
        return -1;
    }
    return 0;
}


- (void)backgroundTask
{
    BOOL mustQuit = NO;
    UMSocketError e;
    
    if(self.name)
    {
        ulib_set_thread_name(self.name);
    }
    NSLog(@"backgroundTask #1");
    if(runningStatus != UMBackgrounder_startingUp)
    {
        NSLog(@"backgroundTask #2");
        return;
    }
    if(workSleeper==NULL)
    {
        self.workSleeper = [[UMSleeper alloc]initFromFile:__FILE__ line:__LINE__ function:__func__];
    }
    runningStatus = UMBackgrounder_running;
    
    [control_sleeper wakeUp:UMSleeper_StartupCompletedSignal];
    
    if(enableLogging)
    {
        NSLog(@"%@: started up successfully",self.name);
    }
    [self backgroundInit];
    while((runningStatus == UMBackgrounder_running) && (mustQuit==NO))
    {
         e= [link dataIsAvailable];
        if((e==UMSocketError_has_data) || (e==UMSocketError_has_data_and_hup))
        {
            [link receiveData];
        }
        if(e==UMSocketError_has_data_and_hup)
        {
            break;
        }
        if((e != UMSocketError_no_error) && (e!=UMSocketError_no_data) && (e!=UMSocketError_has_data))
        {
            break;
        }
    }
    if(enableLogging)
    {
        NSLog(@"%@: shutting down",self.name);
    }
    [self backgroundExit];
    runningStatus = UMBackgrounder_notRunning;
    self.workSleeper = NULL;
    [control_sleeper wakeUp:UMSleeper_ShutdownCompletedSignal];
}
@end
