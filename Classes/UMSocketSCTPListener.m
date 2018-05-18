//
//  UMSocketSCTPListener.m
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPListener.h"
#import "UMSocketSCTP.h"
#import "UMLayerSctp.h"

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
        _layerByAssocId = [[UMSynchronizedDictionary alloc]init];
        _layerByRemoteIPRemotePort = [[UMSynchronizedDictionary alloc]init];
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

- (void)processReceivedData:(UMSocketSCTPReceivedPacket *)rx
{
    /* we need to find the right layer to handle this */
    if(rx.err == UMSocketError_no_error)
    {
        if(rx.assocId)
        {
            UMLayerSctp *layer = _layerByAssocId[rx.assocId];
            if(layer)
            {
                [layer processReceivedData:rx];
            }
            else
            {
                /* we have not seen this association id before */
                /* lets find it by source / destination IP */
                
            }
        }
    }
}

- (void)processHangUp
{
    
}

- (void)processInvalidSocket
{
}

@end
