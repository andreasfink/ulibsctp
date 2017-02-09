//
//  UMSctpTask_Data.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"
@class UMLayerSctp;

@interface UMSctpTask_Data : UMLayerTask
{
    NSData          *data;
    uint16_t        streamId;
    uint32_t        protocolId;
    NSDictionary    *ackRequest;
}

@property (readwrite,strong)        NSData          *data;
@property (readwrite,assign)        uint16_t        streamId;
@property (readwrite,assign)        uint32_t        protocolId;
@property (readwrite,strong)        NSDictionary    *ackRequest;

- (UMSctpTask_Data *)initWithReceiver:(UMLayerSctp *)rx sender:(id<UMLayerSctpUserProtocol>)tx data:(NSData *)d streamId:(uint16_t)sid protocolId:(uint32_t)pid ackRequest:(NSDictionary *)ack;
@end
