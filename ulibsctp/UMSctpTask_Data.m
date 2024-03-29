//
//  UMSctpTask_Data.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSctpTask_Data.h"
#import "UMLayerSctp.h"
#include "ulibsctp_config.h"
#ifdef HAVE_SCTP_SCTP_H
#import <sctp/sctp.h>
#endif

#ifdef HAVE_NETINET_SCTP_H
#include "netinet/sctp.h"
#endif

@implementation UMSctpTask_Data


- (UMSctpTask_Data *)initWithReceiver:(UMLayer *)rx
                               sender:(id<UMLayerSctpUserProtocol>)tx
                                 data:(NSData *)d
                             streamId:(NSNumber *)sid
                           protocolId:(NSNumber *)pid
                           ackRequest:(NSDictionary *)ack
{
    self = [super initWithName:[[self class]description]  receiver:rx sender:tx requiresSynchronisation:NO];
    if(self)
    {
        self.name = @"UMSctpTask_Data";
        _data = d;
        _streamId = sid;
        _protocolId = pid;
        _ackRequest = ack;
    }
    return self;
}

- (void)main
{
    @autoreleasepool
    {
        UMLayerSctp *link = (UMLayerSctp *)self.receiver;
        [link _dataTask:self];
    }
}
@end
