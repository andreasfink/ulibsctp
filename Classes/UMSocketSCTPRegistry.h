//
//  UMSocketSCTPRegistry.h
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
@class UMSocketSCTPListener;
@class UMLayerSctp;
@class UMSocketSCTPReceiver;

@interface UMSocketSCTPRegistry : UMObject
{
    NSMutableDictionary *_entries;
    NSMutableDictionary *_assocs;

    NSMutableArray *_outgoingLayers;
    NSMutableArray *_incomingListeners;
    NSMutableDictionary *_outgoingLayersByIpsAndPorts;
    NSMutableDictionary *_outgoingLayersByAssoc;
    
    UMMutex *_lock;
    UMSocketSCTPReceiver *_receiver;
    BOOL                _receiverStarted;
}

- (NSString *)webStat;

+ (NSString *)keyForPort:(int)port ips:(NSArray<NSString *> *)ips;

- (UMSocketSCTPListener *)listenerForPort:(int)port localIps:(NSArray *)ips;
- (void)unregisterListener:(UMSocketSCTPListener *)e;

- (UMLayerSctp *)layerForAssoc:(NSNumber *)assocId;

- (void)registerLayer:(UMLayerSctp *)layer;
- (void)registerLayer:(UMLayerSctp *)sctp forAssoc:(NSNumber *)assocId;
- (void)unregisterLayer:(UMLayerSctp *)sctp;
- (UMLayerSctp *)layerForLocalIp:(NSString *)ip1
                       localPort:(int)port1
                        remoteIp:(NSString *)ip2
                      remotePort:(int)port2;

- (NSArray *)allListeners;
- (NSArray *)allOutboundLayers;
- (void)startReceiver;
- (void)stopReceiver;

@end
