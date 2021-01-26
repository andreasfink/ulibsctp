//
//  UMSocketSCTPListener.m
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#define ULIBSCTP_INTERNAL 1

#import "UMSocketSCTPListener.h"
#import "UMSocketSCTP.h"
#import "UMLayerSctp.h"
#import "UMSocketSCTPRegistry.h"

@implementation UMSocketSCTPListener

- (UMSocketSCTPListener *)initWithPort:(int)localPort localIpAddresses:(NSArray *)addresses
{
    return [self initWithPort:localPort localIpAddresses:addresses encapsulated:NO];
}

- (UMSocketSCTPListener *)initWithPort:(int)localPort localIpAddresses:(NSArray *)addresses encapsulated:(BOOL)tcpEncapsulated
{
    self = [super init];
    if(self)
    {
        _tcpEncapsulated = tcpEncapsulated;
        _port = localPort;
        NSString *lockName;
        _localIpAddresses = addresses;
        if(_localIpAddresses == NULL)
        {
            _localIpAddresses = @[@"0.0.0.0"];
        }
        if(tcpEncapsulated)
        {
            _name = [NSString stringWithFormat:@"sctptcp-listener:%d",_port];
            lockName = [NSString stringWithFormat:@"sctptcp-listener-lock:%d",_port];
        }
        else
        {
            _name = [NSString stringWithFormat:@"sctp-listener[%@]:%d",[_localIpAddresses componentsJoinedByString:@","],_port];
            lockName = [NSString stringWithFormat:@"sctp-listener-lock[%@]:%d",[_localIpAddresses componentsJoinedByString:@","],_port];
        }
        _isListening = NO;
        _listeningCount = 0;
        _layers = [[UMSynchronizedDictionary alloc]init];
        _lock = [[UMMutex alloc]initWithName:lockName];
        _logLevel = UMLOG_MINOR;
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

- (int)mtu
{
    if(_umsocket)
    {
        return _umsocket.mtu;
    }
    return _configuredMtu;
}

- (void)setMtu:(int)mtu
{
    _configuredMtu = mtu;
    _umsocket.mtu = mtu;
}

- (BOOL) tcapEncapsulating
{
    return NO;
}

- (void)startListeningFor:(UMLayerSctp *)layer
{
    if(layer.encapsulatedOverTcp == YES)
    {
        [self startListeningForTcp:layer];
        return;
    }
    /* multiple UMLayerSctp objects can call startListening and ask a listener to listen for incoming
     packets on a specific port. Only the first such request is actually starting a listening process
     the subsequents just increase the counter. When a layer stops listening then the counter is decreased.
     If all layers stop listening, then the counter reaches zero and the socket is closed.
    */
    [_lock lock];
    if(_isListening)
    {
        _layers[layer.layerName] =layer;
        _listeningCount = _layers.count;
    }
    else
    {
        NSAssert(_umsocket == NULL,@"calling startListening with _umsocket already existing");

        _umsocket = [[UMSocketSCTP alloc]initWithType:UMSOCKET_TYPE_SCTP_SEQPACKET name:_name];
        _umsocket.requestedLocalAddresses = _localIpAddresses;
        _umsocket.requestedLocalPort = _port;
        [_umsocket updateMtu:_configuredMtu];

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
        err = [_umsocket setInitParams];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not set INIT PARMAS on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
        }
        else
        {
            [self logDebug:[NSString stringWithFormat:@"%@: setting INIT PARMAS successful",_name]];
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
        if(_umsocket.socketType != SOCK_SEQPACKET)
        {
            err = [_umsocket setReusePort];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not set SCTP_REUSE_PORT option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  setReusePort successful",_name]];
            }
        }
        err = [_umsocket enableEvents];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not enable sctp events on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
        }
        else
        {
            [self logDebug:[NSString stringWithFormat:@"%@:  enableEvents successful",_name]];
            err = [_umsocket bind];
            if(err!=UMSocketError_no_error)
            {
                [self logMajorError:[NSString stringWithFormat:@"can not bind on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  bind successful",_name]];
                err = [_umsocket listen:128];
                if(err!=UMSocketError_no_error)
                {
                    [self logMinorError:[NSString stringWithFormat:@"can not enable sctp events on sctp-listener port %d: %d %@",_port,err,[UMSocket getSocketErrorString:err]]];
                }
                else
                {
                    [self logDebug:[NSString stringWithFormat:@"%@:  listen successful",_name]];
                    _isListening = YES;
                    _listeningCount++;
                }
            }
        }
        err =[_umsocket setHeartbeat:YES];
        if(err!=UMSocketError_no_error)
        {
            NSString *estr = [UMSocket getSocketErrorString:err];
            NSString *s = [NSString stringWithFormat:@"%@:  can not enable heartbeat %@",_name,estr];
            [self logMinorError:s];
        }
    }
    if(_isListening==NO)
    {
        [_umsocket close];
        _umsocket = NULL;
    }
    [_lock unlock];
}

- (void)startListeningForTcp:(UMLayerSctp *)layer
{
    /* multiple UMLayerSctp objects can call startListening and ask a listener to listen for incoming
     packets on a specific tcp port. Only the first such request is actually starting a listening process
     the subsequents just increase the counter. When a layer stops listening then the counter is decreased.
     If all layers stop listening, then the counter reaches zero and the socket is closed.
    */

    [_lock lock];
    if(_isListening)
    {
        _layers[layer.layerName] =layer;
        _listeningCount = _layers.count;
    }
    else
    {
        NSAssert(_umsocket == NULL,@"calling startListening with _umsocket already existing");

        _umsocketEncapsulated = [[UMSocket alloc]initWithType:UMSOCKET_TYPE_TCP name:_name];
        _umsocketEncapsulated.localHost = [[UMHost alloc]initWithLocalhost];
        _umsocketEncapsulated.requestedLocalPort = _port;
        [_umsocketEncapsulated switchToNonBlocking];
        UMSocketError err = [_umsocket setIPDualStack];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not disable IPV6_V6ONLY option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
        }
        else
        {
            [self logDebug:[NSString stringWithFormat:@"%@:  setIPDualStack successful",_name]];
        }
        err = [_umsocketEncapsulated setLinger];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not set SO_LINGER option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
        }
        else
        {
            [self logDebug:[NSString stringWithFormat:@"%@:  setLinger successful",_name]];
        }

        err = [_umsocketEncapsulated setReuseAddr];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not set SO_REUSEADDR option on %@: %d %@",_name,err,[UMSocket getSocketErrorString:err]]];
        }
        else
        {
            [self logDebug:[NSString stringWithFormat:@"%@:  setReuseAddr successful",_name]];
        }
        
        err = [_umsocketEncapsulated bind];
        if(err == UMSocketError_no_error)
        {
            [self logDebug:[NSString stringWithFormat:@"%@:  bind successful",_name]];
            err = [_umsocketEncapsulated listen:128];
            if(err!=UMSocketError_no_error)
            {
                [self logMinorError:[NSString stringWithFormat:@"can not enable sctp events on sctp-listener port %d: %d %@",_port,err,[UMSocket getSocketErrorString:err]]];
            }
            else
            {
                [self logDebug:[NSString stringWithFormat:@"%@:  listen successful",_name]];
                _isListening = YES;
                _listeningCount++;
            }
        }
    }
    if(_isListening==NO)
    {
        [_umsocketEncapsulated close];
        _umsocketEncapsulated = NULL;
    }
    [_lock unlock];
}

- (void)stopListeningFor:(UMLayerSctp *)layer
{
    [_lock lock];
    [_layers removeObjectForKey:layer.layerName];
    _listeningCount = _layers.count;
    if(_listeningCount<=0)
    {
        if(_tcpEncapsulated)
        {
            [_registry removeTcpListener:self];
        }
        else
        {
            [_registry removeListener:self];
        }
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
#if defined(ULIBSCTP_CONFIG_DEBUG)
    NSLog(@"Processing received data: \n%@",rx);
#endif
    if(rx.err == UMSocketError_no_error)
    {
        BOOL processed=NO;
        if(rx.assocId != NULL)
        {
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"Looking into registry: %@",_registry);
#endif
            UMLayerSctp *layer =  [_registry layerForAssoc:rx.assocId];
            if(layer)
            {
                [layer processReceivedData:rx];
                processed = YES;
            }
        }
        if(processed==NO)
        {
            /* we have not seen this association id before */
            /* lets find it by source / destination IP */
            for(NSString *ip in _localIpAddresses)
            {
#if defined(ULIBSCTP_CONFIG_DEBUG)
                NSLog(@"_registry\n\tlayerForLocalIp:%@\n\tlocalPort:%d\n\tremoteIp:%@\n\tremotePort:%d\n",ip,_port,rx.remoteAddress,rx.remotePort);
#endif
                UMLayerSctp *layer = [_registry layerForLocalIp:ip
                                                      localPort:_port
                                                       remoteIp:rx.remoteAddress
                                                     remotePort:rx.remotePort];
                if(layer)
                {
                    [layer processReceivedData:rx];
                    processed=YES;
                }
            }
        }
        if((processed==NO) && (_sendAborts))
        {
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"sending abort");
#endif

            uint32_t assoc = rx.assocId.unsignedIntValue;
            UMSocketError err = [_umsocket abortToAddress:rx.remoteAddress
                                                     port:rx.remotePort
                                                    assoc:assoc
                                                   stream:rx.streamId
                                                 protocol:rx.protocolId];
            if(err !=UMSocketError_no_error)
            {
                NSLog(@"abortToAddress  %@ port %d. error %@",rx.remoteAddress,rx.remotePort, [UMSocket getSocketErrorString:err]);
            }
        }
    }
}

- (void)abortPeer
{
}

- (void)processError:(UMSocketError)err
{
    /* FIXME */
    NSLog(@"processError %d %@ received in listener %@",err, [UMSocket getSocketErrorString:err], _name);
}

- (void)processHangUp
{
    /* FIXME */
    NSLog(@"processHangUp received in listener %@",_name);
}

- (void)processInvalidSocket
{
    /* FIXME */
    NSLog(@"processInvalidSocket received in listener %@",_name);
    _isInvalid = YES;
}

- (UMSocketError) connectToAddresses:(NSArray *)addrs
                                port:(int)port
                               assoc:(uint32_t *)assocptr
                               layer:(UMLayerSctp *)layer
{

    if(_logLevel == UMLOG_DEBUG)
    {
        NSLog(@"connectToAddresses:%@ port:%d",[addrs componentsJoinedByString:@","],port);
    }
    if(_isListening==NO)
    {
        [self startListeningFor:layer];
    }
    UMSocketError err = [_umsocket connectToAddresses:addrs
                                                 port:port
                                                assoc:assocptr];
    if(assocptr)
    {
        if(_logLevel == UMLOG_DEBUG)
        {
            NSLog(@"   returns assoc=%ld",(long)*assocptr);
        }
    }
    return err;
}

- (UMSocketSCTP *) peelOffAssoc:(uint32_t)assoc error:(UMSocketError *)errptr
{
    return [_umsocket peelOffAssoc:assoc error:errptr];
}


- (ssize_t) sendToAddresses:(NSArray *)addrs
                       port:(int)remotePort
                      assoc:(uint32_t *)assocptr
                       data:(NSData *)data
                     stream:(uint16_t)streamId
                   protocol:(u_int32_t)protocolId
                      error:(UMSocketError *)err2
                      layer:(UMLayerSctp *)layer
{
    ssize_t r = -1;
    [self startListeningFor:layer];

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(layer.newDestination)
    {
        [self logDebug:@" layer.newDestination=YES"];
    }
    else
    {
        [self logDebug:@" layer.newDestination=NO"];
    }
#endif
    if(layer.status != UMSOCKET_STATUS_IS)
    {
        UMSocketError err = [_umsocket connectToAddresses:addrs
                                                     port:remotePort
                                                    assoc:assocptr];
        if(err!=UMSocketError_no_error)
        {
            NSString *estr = [UMSocket getSocketErrorString:err];
            NSString *s = [NSString stringWithFormat:@"%@:  can not connectx: %@",_name,estr];
            [self logMinorError:s];
        }
    }
    if(layer.newDestination==YES)
    {
        [_umsocket updateMtu:_configuredMtu];
        UMSocketError err = [_umsocket setHeartbeat:YES];
        if(err!=UMSocketError_no_error)
        {
            NSString *estr = [UMSocket getSocketErrorString:err];
            NSString *s = [NSString stringWithFormat:@"%@:  can not enable heartbeat %@",_name,estr];
            [self logMinorError:s];
        }
        layer.newDestination = NO;
    }
    r = [_umsocket sendToAddresses:addrs
                              port:remotePort
                             assoc:assocptr
                              data:data
                            stream:streamId
                          protocol:protocolId
                             error:err2];
    return r;
}

- (BOOL) isTcpEncapsulated
{
    if((_umsocket == NULL) && (_umsocketEncapsulated != NULL))
    {
        return YES;
    }
    return NO;
}

- (NSString *)description
{
    NSMutableString *s = [[NSMutableString alloc]init];
    [s appendFormat:@"UMSocketListener %@ (%@:%d) %@",_name,[_localIpAddresses componentsJoinedByString:@","], _port, self.isTcpEncapsulated ? @"tcpencap=yes" : @""];
    return s;
}
@end
