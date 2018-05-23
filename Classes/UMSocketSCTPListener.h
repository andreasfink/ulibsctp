//
//  UMSocketSCTPListener.h
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMSocketSCTP.h"

@class UMSocketSCTPRegistry;

@interface UMSocketSCTPListener : UMObject
{
    int         _port;
    NSArray *   _localIps;
    UMSocketSCTP *_umsocket;
    BOOL        _isListening;
    UMMutex     *_lock;
    int         _listeningCount;
    UMSocketSCTPRegistry *_registry;
    NSString    *_name;
}

@property(readwrite,assign) int port;
@property(readwrite,strong) NSArray *localIps;
@property(readwrite,strong) UMSocketSCTP *umsocket;
@property(readwrite,strong) UMSocketSCTPRegistry *registry;
@property(readwrite,strong) NSString *name;

- (UMSocketSCTPListener *)initWithPort:(int)port localIpAddresses:(NSArray *)addresses;
- (void)startListening;
- (void)stopListening;
- (void)processReceivedData:(UMSocketSCTPReceivedPacket *)rx;
- (void)processHangUp;
- (void)processInvalidSocket;
- (UMSocketError) connectToAddresses:(NSArray *)addrs port:(int)port assoc:(sctp_assoc_t *)assoc;
@end
