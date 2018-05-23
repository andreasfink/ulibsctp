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
#import "UMSocketSCTPRegistry.h"

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
        _name = [NSString stringWithFormat:@"sctp-listener[%@]:%d",[addresses componentsJoinedByString:@","],_port];
    }
    return self;
}
- (void)logMinorError:(NSString *)s
{
    NSLog(@"%@",s);
}

- (void)logMajorError:(NSString *)s
{
    NSLog(@"%@",s);
}

- (void)logDebug:(NSString *)s
{
    NSLog(@"%@",s);
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
            _umsocket = [[UMSocketSCTP alloc]initWithType:UMSOCKET_TYPE_SCTP name:_name];

            _umsocket.requestedLocalAddresses = _localIps;
            _umsocket.requestedLocalPort = _port;


            [_umsocket switchToNonBlocking];

            UMSocketError err = [_umsocket setNoDelay];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not set NODELAY option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@: setting NODELAY successful",_name]];
            }

            err = [_umsocket setIPDualStack];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not disable IPV6_V6ONLY option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  setIPDualStack successful",_name]];
            }

            err = [_umsocket setLinger];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not set SO_LINGER option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  setLinger successful",_name]];
            }

            err = [_umsocket setReuseAddr];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not set SO_REUSEADDR option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  setReuseAddr successful",_name]];
            }
            err = [_umsocket setReusePort];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not set SCTP_REUSE_PORT option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  setReusePort successful",_name]];
            }
            err = [_umsocket enableEvents];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not enable sctp events on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
                return;
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  enableEvents successful",_name]];
            }

            err = [_umsocket enableFutureAssoc];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not enableFutureAssocon %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
                return;
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  enableFutureAssoc successful",_name]];
            }

            err = [_umsocket bind];
            if(err!=UMSocketError_no_error)
            {
                [self logMajorError:[NSString stringWithFormat:@"can not bind on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
                return;
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  bind successful",_name]];
            }
            err = [_umsocket listen];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not enable sctp events on sctp-listener port %d: %d %@",_port,err,[UMSocket getSocketErrorString:err]]];
                return;
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  listen successful",_name]];
            }
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
        [_registry unregisterListener:self];
        [_umsocket close];
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
#if (ULIBSCTP_CONFIG==Debug)
    NSLog(@"Processing received data: \n%@",rx);
#endif
    if(rx.err == UMSocketError_no_error)
    {
        if(rx.assocId)
        {
#if (ULIBSCTP_CONFIG==Debug)
            NSLog(@"Lookign into registry: %@",_registry);
#endif
            UMLayerSctp *layer =  [_registry layerForAssoc:rx.assocId];
            if(layer)
            {
                [layer processReceivedData:rx];
            }
            else
            {
                /* we have not seen this association id before */
                /* lets find it by source / destination IP */
                for(NSString *localIp in _localIps)
                {
                    layer = [_registry layerForLocalIp:localIp
                                             localPort:_port
                                              remoteIp:rx.remoteAddress
                                            remotePort:rx.remotePort];
                    if(layer)
                    {
                        [layer processReceivedData:rx];
                        break;
                    }
                }
                if(layer == NULL)
                {
                    /* we have not found anyone listening to this so we send abort */
                    NSLog(@"should abort here for %@ %d",rx.remoteAddress,rx.remotePort);
                }
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
