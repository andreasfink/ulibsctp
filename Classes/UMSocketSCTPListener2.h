//
//  UMSocketSCTPListener2.h
//  ulibsctp
//
//  Created by Andreas Fink on 25.08.22.
//  Copyright © 2022 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMSCTPListener.h"
#import "UMSocketSCTP.h"

@class UMSocketSCTPRegistry;
@class UMLayerSctp;

@interface UMSocketSCTPListener2 : UMSCTPListener<UMSCTPListenerProcessEventsDelegate, UMSCTPListenerProcessDataDelegate,UMSCTPListenerReadPacketDelegate>
{
    int                         _port;
    NSArray *                   _localIpAddresses;
    BOOL                        _isBound;
    BOOL                        _isListening;
    UMMutex                     *_lock;
    UMSocketSCTPRegistry        *_registry;
    UMSynchronizedDictionary    *_layers;
    NSNumber                    *_configuredMtu;
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
@property(readwrite,strong) UMSocket *umsocketEncapsulated;
@property(readwrite,strong) UMSocketSCTPRegistry *registry;
@property(readwrite,assign) BOOL    isListening;
@property(readwrite,strong) NSNumber *configuredMtu;
@property(readwrite,assign) BOOL    firstMessage;
@property(readwrite,assign) BOOL    isInvalid;
@property(readwrite,assign) BOOL    sendAborts;
@property(readwrite,assign) UMLogLevel logLevel;
@property(readonly,assign)  BOOL tcpEncapsulated;
@property(readwrite,assign) int minReceiveBufferSize;
@property(readwrite,assign) int minSendBufferSize;
@property(readwrite,strong) NSString *dscp;

- (UMSocketSCTPListener2 *)initWithPort:(int)localPort localIpAddresses:(NSArray *)addresses;



- (void) processError:(UMSocketError)err;
- (void) processHangup;
- (void) processInvalidValue;
- (void) processReceivedData:(UMSocketSCTPReceivedPacket *)rx;
- (UMSocketSCTPReceivedPacket *)receiveSCTP;


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

