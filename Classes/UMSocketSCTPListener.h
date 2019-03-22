//
//  UMSocketSCTPListener.h
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMSocketSCTP.h"


#ifdef	FREEBSD
#ifndef sctp_assoc_t
typedef uint32_t sctp_assoc_t;
#endif
#endif

@class UMSocketSCTPRegistry;
@class UMLayerSctp;

@interface UMSocketSCTPListener : UMObject
{
    int                         _port;
    NSArray *                   _localIpAddresses;
    UMSocketSCTP                *_umsocket;
    BOOL                        _isListening;
    UMMutex                     *_lock;
    NSInteger                   _listeningCount;
    UMSocketSCTPRegistry        *_registry;
    NSString                    *_name;
    UMSynchronizedDictionary    *_layers;
    int                         _configuredMtu;
    BOOL                        _firstMessage;
    BOOL                        _isInvalid;
    UMLogLevel                  _logLevel;
}

@property(readwrite,assign) int port;
@property(readwrite,strong) NSArray *localIpAddresses;
@property(readwrite,strong) UMSocketSCTP *umsocket;
@property(readwrite,strong) UMSocketSCTPRegistry *registry;
@property(readwrite,strong) NSString *name;
@property(readwrite,assign) BOOL    isListening;
@property(readwrite,assign) int     mtu;
@property(readwrite,assign) BOOL    firstMessage;
@property(readwrite,assign) BOOL    isInvalid;
@property(readwrite,assign) UMLogLevel logLevel;

- (UMSocketSCTPListener *)initWithPort:(int)port localIpAddresses:(NSArray *)addresses;
- (void)startListeningFor:(UMLayerSctp *)layer;
- (void)stopListeningFor:(UMLayerSctp *)layer;
- (void)processReceivedData:(UMSocketSCTPReceivedPacket *)rx;
- (void)processError:(UMSocketError)err;
- (void)processHangUp;
- (void)processInvalidSocket;

#if defined(ULIBSCTP_INTERNAL)
- (UMSocketError) connectToAddresses:(NSArray *)addrs
                                port:(int)port
                               assoc:(sctp_assoc_t *)assoc
                               layer:(UMLayerSctp *)layer;
- (UMSocketSCTP *) peelOffAssoc:(sctp_assoc_t)assoc error:(UMSocketError *)errptr;

- (ssize_t) sendToAddresses:(NSArray *)addrs
                       port:(int)remotePort
                      assoc:(sctp_assoc_t *)assocptr
                       data:(NSData *)data
                     stream:(uint16_t)streamId
                   protocol:(u_int32_t)protocolId
                      error:(UMSocketError *)err2
                      layer:(UMLayerSctp *)layer;
#endif

@end
