//
//  UMSctpTask_AdminInit.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright (c) 2016 Andreas Fink
//

#import "UMSctpTask_AdminInit.h"
#import "UMLayerSctp.h"

@implementation UMSctpTask_AdminInit

- (UMSctpTask_AdminInit *)initWithReceiver:(UMLayer *)rx sender:(id<UMLayerSctpUserProtocol>)tx
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:tx
       requiresSynchronisation:NO];
    if(self)
    {
    }
    return self;
}

- (void)main
{
    UMLayerSctp *link = (UMLayerSctp *)self.receiver;
    [link _adminInitTask:self];
}

@end
