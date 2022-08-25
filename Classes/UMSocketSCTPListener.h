//
//  UMSocketSCTPListener.h
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#ifdef USE_LISTENER1

#import <ulib/ulib.h>
#import "UMSocketSCTP.h"



@class UMSocketSCTPRegistry;
@class UMLayerSctp;

@interface UMSocketSCTPListener : UMObject
{
    int                         _port;
    NSArray *                   _localIpAddresses;
    UMSocketSCTP                *_umsocket;
    UMSocket                    *_umsocketEncapsulated;
    BOOL                        _isListening;
    UMMutex                     *_lock;
    NSInteger                   _listeningCount;
    UMSocketSCTPRegistry        *_registry;
    NSString                    *_name;
    UMSynchronizedDictionary    *_layers;
    int                         _configuredMtu;
    BOOL                        _firstMessage;
    BOOL                        _isInvalid;
    BOOL                        _sendAborts;
    BOOL                        _tcpEncapsulated;
    UMLogLevel                  _logLevel;
    int                         _minReceiveBufferSize;
    int                         _minSendBufferSize;
    NSString                    *_dscp;
}

@property(readwrite,assign) int port;
@property(readwrite,strong) NSArray *localIpAddresses;
@property(readwrite,strong) UMSocketSCTP *umsocket;
@property(readwrite,strong) UMSocket *umsocketEncapsulated;
@property(readwrite,strong) UMSocketSCTPRegistry *registry;
@property(readwrite,strong) NSString *name;
@property(readwrite,assign) BOOL    isListening;
@property(readwrite,assign) int     mtu;
@property(readwrite,assign) BOOL    firstMessage;
@property(readwrite,assign) BOOL    isInvalid;
@property(readwrite,assign) BOOL    sendAborts;
@property(readwrite,assign) UMLogLevel logLevel;
@property(readonly,assign)  BOOL tcpEncapsulated;
@property(readwrite,assign) int minReceiveBufferSize;
@property(readwrite,assign) int minSendBufferSize;
@property(readwrite,strong) NSString *dscp;

- (UMSocketSCTPListener *)initWithPort:(int)port localIpAddresses:(NSArray *)addresses;
- (UMSocketSCTPListener *)initWithPort:(int)localPort localIpAddresses:(NSArray *)addresses encapsulated:(BOOL)tcpEncapsulated;
- (void)startListeningFor:(UMLayerSctp *)layer;
- (void)startListeningForTcp:(UMLayerSctp *)layer;

- (void)stopListeningFor:(UMLayerSctp *)layer;
- (void)processReceivedData:(UMSocketSCTPReceivedPacket *)rx;
- (void)processError:(UMSocketError)err socket:(UMSocket *)s inArea:(NSString *)area;
- (void)processHangUp;
- (void)processInvalidSocket;

- (void)logMinorError:(NSString *)s;
- (void)logMajorError:(NSString *)s;
- (void)logDebug:(NSString *)s;
- (int)mtu;
- (void)setMtu:(int)mtu;


#if defined(ULIBSCTP_INTERNAL)
- (UMSocketError) connectToAddresses:(NSArray *)addrs
                                port:(int)port
                            assocPtr:(NSNumber **)assoc
                               layer:(UMLayerSctp *)layer;
- (UMSocketSCTP *) peelOffAssoc:(NSNumber *)assoc
                          error:(UMSocketError *)errptr;

- (ssize_t) sendToAddresses:(NSArray *)addrs
                       port:(int)remotePort
                   assocPtr:(NSNumber **)assocptr
                       data:(NSData *)data
                     stream:(NSNumber *)streamId
                   protocol:(NSNumber *)protocolId
                      error:(UMSocketError *)err2
                      layer:(UMLayerSctp *)layer;
#endif

@end
#endif

