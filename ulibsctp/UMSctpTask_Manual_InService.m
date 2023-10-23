//
//  UMSctpTask_Manual_InService.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSctpTask_Manual_InService.h"
#import "UMLayerSctp.h"
#import "UMLayerSctpUserProtocol.h"

@implementation UMSctpTask_Manual_InService

- (UMSctpTask_Manual_InService *)initWithReceiver:(UMLayerSctp *)rx
                                           sender:(id<UMLayerSctpUserProtocol>)tx
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:tx
       requiresSynchronisation:NO];
    if(self)
    {
        self.name = @"UMSctpTask_Manual_InService";
    }
    return self;
}

-(void)main
{
    @autoreleasepool
    {
        UMLayerSctp *link = (UMLayerSctp *)self.receiver;
        [link _isTask:self];
    }
}



@end
