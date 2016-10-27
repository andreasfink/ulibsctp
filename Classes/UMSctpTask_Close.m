//
//  UMSctpTask_Close.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright (c) 2016 Andreas Fink
//

#import "UMSctpTask_Close.h"
#import "UMLayerSctp.h"

@implementation UMSctpTask_Close


- (UMSctpTask_Close *)initWithReceiver:(UMLayer *)rx sender:(id<UMLayerSctpUserProtocol>)tx
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:tx
       requiresSynchronisation:YES];
    if(self)
    {
        self.name = @"UMSctpTask_Close";
    }
    return self;
}

- (void)main
{
    UMLayerSctp *link = (UMLayerSctp *)self.receiver;
    [link _closeTask:self];
}

@end
