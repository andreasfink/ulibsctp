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
@class UMSocketSCTPTCPListener;

@interface UMSocketSCTPRegistry : UMObject
{
    NSMutableDictionary     *_entries;
    NSMutableDictionary     *_assocs;

    NSMutableArray          *_outgoingLayers;
    NSMutableArray<UMSocketSCTPListener *>      *_incomingListeners;
    NSMutableDictionary<NSNumber *,UMSocketSCTPTCPListener *>   *_incomingTcpListeners; /* key is @(port) */
    NSMutableArray          *_incomingLayers; /* once peeled of the listener */
    
    NSMutableArray          *_outgoingTcpLayers;
    NSMutableArray          *_incomingTcpLayers;

    NSMutableDictionary     *_outgoingLayersByIpsAndPorts;
    NSMutableDictionary     *_outgoingLayersByAssoc;
    
    UMMutex *_lock;
    UMSocketSCTPReceiver    *_receiver;
    BOOL                    _receiverStarted;
    BOOL                    _sendAborts;
    UMLogLevel              _logLevel;
    NSMutableDictionary     *_layersBySessionKey;
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

- (UMSocketSCTPTCPListener *)getOrAddTcpListenerForPort:(int)port;
- (UMSocketSCTPTCPListener *)getTcpListenerForPort:(int)port;
- (void)addTcpListener:(UMSocketSCTPTCPListener *)listener;
- (void)removeTcpListener:(UMSocketSCTPTCPListener *)listener;

- (void)registerSessionKey:(NSString *)session_key forLayer:(UMLayerSctp *)layer;
- (void)unregisterSessionKey:(NSString *)session_key;


//- (UMSocketSCTPListener *)listenerForPort:(int)port localIps:(NSArray *)ips;
//- (void)unregisterListener:(UMSocketSCTPListener *)e;

- (UMLayerSctp *)layerForAssoc:(NSNumber *)assocId;
- (UMLayerSctp *)layerForSessionKey:(NSString *)sessionKey;

- (void)registerOutgoingLayer:(UMLayerSctp *)layer;
- (void)registerOutgoingTcpLayer:(UMLayerSctp *)layer;
- (void)registerOutgoingLayer:(UMLayerSctp *)layer allowAnyRemotePortIncoming:(BOOL)anyPort;

- (void)registerIncomingLayer:(UMLayerSctp *)layer;
- (void)registerIncomingTcpLayer:(UMLayerSctp *)layer;

- (void)registerAssoc:(NSNumber *)assocId forLayer:(UMLayerSctp *)layer;

- (void)unregisterAssoc:(NSNumber *)assocId;

- (void)unregisterLayer:(UMLayerSctp *)sctp;
- (UMLayerSctp *)layerForLocalIp:(NSString *)ip1
                       localPort:(int)port1
                        remoteIp:(NSString *)ip2
                      remotePort:(int)port2;

- (NSArray *)allListeners;
- (NSArray *)allTcpListeners;
- (NSArray *)allOutboundLayers;
- (NSArray *)allInboundLayers;

- (NSArray *)allOutboundTcpLayers;
- (NSArray *)allInboundTcpLayers;

- (void)unregisterIncomingTcpLayer:(UMLayerSctp *)layer;

- (void)startReceiver;
- (void)stopReceiver;

@end
