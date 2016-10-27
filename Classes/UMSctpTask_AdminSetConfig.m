//
//  UMSctpTask_AdminSetConfig.m
//  ulibsctp
//
//  Created by Andreas Fink on 01.12.14.
//  Copyright (c) 2016 Andreas Fink
//

#import "UMSctpTask_AdminSetConfig.h"
#import "UMLayerSctp.h"

@implementation UMSctpTask_AdminSetConfig

@synthesize config;

- (UMSctpTask_AdminSetConfig *)initWithReceiver:(UMLayer *)rx config:(NSDictionary *)cfg
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:NULL
       requiresSynchronisation:YES];
    if(self)
    {
        self.name = @"UMSctpTask_AdminSetConfig";
        self.config = cfg;
    }
    return self;
}

- (void)main
{
    UMLayerSctp *link = (UMLayerSctp *)self.receiver;
    [link _adminSetConfigTask:self];
}


@end
