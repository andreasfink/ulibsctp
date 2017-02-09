//
//  UMSctpTask_Open.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSctpTask_Open.h"
#import "UMLayerSctp.h"

#include <sys/errno.h>
#include <unistd.h>
#include <sys/types.h>
#ifdef __APPLE__
#import <sctp/sctp.h>
#else
#include "netinet/sctp.h"
#endif
#include <arpa/inet.h>
#import "UMLayerSctpReceiverThread.h"

@implementation UMSctpTask_Open


- (UMSctpTask_Open *)initWithReceiver:(UMLayer *)rx sender:(id<UMLayerSctpUserProtocol>)tx
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:tx
       requiresSynchronisation:NO];
    if(self)
    {
        self.name = @"UMSctpTask_Open";
    }
    return self;
}

- (void)main
{
    UMLayerSctp *link = (UMLayerSctp *)self.receiver;
    [link _openTask:self];
}

@end
