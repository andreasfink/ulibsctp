//
//  UMSctpTask_Manual_ForceOutOfService.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright (c) 2016 Andreas Fink
//

#import "UMSctpTask_Manual_ForceOutOfService.h"

@implementation UMSctpTask_Manual_ForceOutOfService

- (UMSctpTask_Manual_ForceOutOfService *)initWithReceiver:(UMLayerSctp *)rx
                                                   sender:(id<UMLayerSctpUserProtocol>)tx
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:tx
       requiresSynchronisation:YES];
    if(self)
    {
        self.name = @"UMSctpTask_Manual_ForceOutOfService";
    }
    return self;
}

-(void)main
{
    UMLayerSctp *link = (UMLayerSctp *)self.receiver;
    [link _foosTask:self];
}
@end
