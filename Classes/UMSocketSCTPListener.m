//
//  UMSocketSCTPListener.m
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPListener.h"
#import "UMSocketSCTP.h"

@implementation UMSocketSCTPListener

- (UMSocketSCTPListener *)initWithPort:(int)port localIpAddresses:(NSArray *)addresses
{
    self = [super init];
    if(self)
    {
        _port = port;
        _localIps = addresses;
        _isListening = NO;
        _listeningCount = 0;
    }
    return self;
}

- (void)startListening
{
    [_lock lock];
    if(_isListening)
    {
        _listeningCount++;
    }
    else
    {
        if(_umsocket==NULL)
        {
            if(_umsocket)
            {
                [_umsocket close];
            }
            _umsocket = [[UMSocketSCTP alloc]init];
            _umsocket.requestedLocalAddresses = _localIps;
            _umsocket.requestedLocalPort = _port;
            
            [_umsocket switchToNonBlocking];
            [_umsocket setIPDualStack];
            [_umsocket setLinger];
            [_umsocket setReuseAddr];
            [_umsocket setReusePort];
            [_umsocket setNoDelay];
            [_umsocket enableEvents];
            [_umsocket bind];
            [_umsocket listen];
            _isListening = YES;
            _listeningCount++;
        }
    }
    [_lock unlock];
}

- (void)stopListening
{
    [_lock lock];
    _listeningCount--;
    if(_listeningCount<=0)
    {
        if(_umsocket)
        {
            [_umsocket close];
        }
        _umsocket=NULL;
        _listeningCount = 0;
    }
    [_lock unlock];
}

- (void)dealloc
{
    [_umsocket close];
}

@end
