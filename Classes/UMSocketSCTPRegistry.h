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
    NSMutableDictionary     *_entries;
    NSMutableDictionary     *_assocs;

    NSMutableArray          *_outgoingLayers;
    NSMutableArray          *_incomingListeners;
    NSMutableArray          *_incomingLayers; /* once peeled of the listener */
    NSMutableDictionary     *_outgoingLayersByIpsAndPorts;
    NSMutableDictionary     *_outgoingLayersByAssoc;
    
    UMMutex *_lock;
    UMSocketSCTPReceiver    *_receiver;
    BOOL                    _receiverStarted;
    BOOL                    _sendAborts;
    UMLogLevel              _logLevel;
}

@property (readwrite,assign,atomic)   UMLogLevel logLevel;
@property (readwrite,assign,atomic)   BOOL sendAborts;


- (NSString *)webStat;

+ (NSString *)keyForPort:(int)port ip:(NSString *)ip;

- (UMSocketSCTPListener *)getOrAddListenerForPort:(int)port localIps:(NSArray<NSString *> *)ips;
- (UMSocketSCTPListener *)getListenerForPort:(int)port localIp:(NSString *)ip;
- (UMSocketSCTPListener *)getListenerForPort:(int)port localIps:(NSArray *)ips;

- (void)addListener:(UMSocketSCTPListener *)listener;
- (void)addListener:(UMSocketSCTPListener *)listener forPort:(int)port localIp:(NSString *)ip;
- (void)removeListener:(UMSocketSCTPListener *)listener;
- (void)removeListener:(UMSocketSCTPListener *)listener forPort:(int)port localIp:(NSString *)ips;

//- (UMSocketSCTPListener *)listenerForPort:(int)port localIps:(NSArray *)ips;
//- (void)unregisterListener:(UMSocketSCTPListener *)e;

- (UMLayerSctp *)layerForAssoc:(NSNumber *)assocId;

- (void)registerOutgoingLayer:(UMLayerSctp *)layer;
- (void)registerOutgoingLayer:(UMLayerSctp *)layer allowAnyRemotePortIncoming:(BOOL)anyPort;

- (void)registerIncomingLayer:(UMLayerSctp *)layer;
- (void)registerAssoc:(NSNumber *)assocId forLayer:(UMLayerSctp *)layer;

- (void)unregisterAssoc:(NSNumber *)assocId;

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
