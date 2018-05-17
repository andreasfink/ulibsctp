//
//  UMSocketSCTPListener.h
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMSocketSCTP.h"

@interface UMSocketSCTPListener : UMObject
{
    int         _port;
    NSArray *   _localIps;
    UMSocketSCTP *_umsocket;
    BOOL        _isListening;
    UMMutex     *_lock;
    int         _listeningCount;
}

@property(readwrite,assign) int port;
@property(readwrite,assign) int socket;
@property(readwrite,strong) NSArray *localIps;
@property(readwrite,strong) UMSocketSCTP *umsocket;

- (UMSocketSCTPListener *)initWithPort:(int)port localIpAddresses:(NSArray *)addresses;
- (void)startListening;
- (void)stopListening;

@end
