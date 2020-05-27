//
//  UMSctpTask_Manual_ForceOutOfService.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSctpTask_Manual_ForceOutOfService.h"

@implementation UMSctpTask_Manual_ForceOutOfService

- (UMSctpTask_Manual_ForceOutOfService *)initWithReceiver:(UMLayerSctp *)rx
                                                   sender:(id<UMLayerSctpUserProtocol>)tx
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:tx
       requiresSynchronisation:NO];
    if(self)
    {
        self.name = @"UMSctpTask_Manual_ForceOutOfService";
    }
    return self;
}

-(void)main
{
    @autoreleasepool
    {
        UMLayerSctp *link = (UMLayerSctp *)self.receiver;
        [link _foosTask:self];
    }
}
@end
