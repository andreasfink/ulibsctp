//
//  UMSctpTask_Data.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright (c) 2016 Andreas Fink
//

#import "UMSctpTask_Data.h"
#import "UMLayerSctp.h"
#ifdef __APPLE__
#import <sctp/sctp.h>
#else
#include "netinet/sctp.h"
#endif

@implementation UMSctpTask_Data

@synthesize data;
@synthesize streamId;
@synthesize protocolId;
@synthesize ackRequest;

- (UMSctpTask_Data *)initWithReceiver:(UMLayer *)rx
                               sender:(id<UMLayerSctpUserProtocol>)tx
                                 data:(NSData *)d
                             streamId:(uint16_t)sid
                           protocolId:(uint32_t)pid
                           ackRequest:(NSDictionary *)ack
{
    self = [super initWithName:[[self class]description]  receiver:rx sender:tx requiresSynchronisation:YES];
    if(self)
    {
        self.name = @"UMSctpTask_Data";
        self.data = d;
        self.streamId = sid;
        self.protocolId = pid;
        self.ackRequest = ack;
    }
    return self;
}

- (void)main
{
    UMLayerSctp *link = (UMLayerSctp *)self.receiver;
    [link _dataTask:self];
}
@end
