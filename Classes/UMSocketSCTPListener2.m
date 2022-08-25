//
//  UMSocketSCTPListener2.m
//  ulibsctp
//
//  Created by Andreas Fink on 25.08.22.
//  Copyright © 2022 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPListener2.h"
#import "UMSocketSCTPRegistry.h"
#import "UMLayerSctp.h"

@implementation UMSocketSCTPListener2

- (void)dealloc
{
    [_umsocket close];
    [_umsocketEncapsulated close];
    _umsocket = NULL;
    _umsocketEncapsulated = NULL;
    _isInvalid=YES;
}


- (UMSocketSCTPListener2 *)initWithPort:(int)localPort
                      localIpAddresses:(NSArray *)addresses
{
    NSString *name = [NSString stringWithFormat:@"listener_%d",_port];

    self = [super initWithName:name socket:NULL eventDelegate:self readDelegate:self processDelegate:self];
    if(self)
    {
        _logLevel = UMLOG_MINOR;
        _name = [NSString stringWithFormat:@"listener_%d",_port];
        _lock = [[UMMutex alloc]initWithName:_name];
        _isInvalid=NO;
        if(_localIpAddresses == NULL)
        {
            _localIpAddresses = @[@"0.0.0.0"];
        }
    }
    return self;
}

- (void)backgroundInit
{
    _umsocket = [[UMSocketSCTP alloc]initWithType:UMSOCKET_TYPE_SCTP_SEQPACKET name:_name];
    _umsocket.requestedLocalAddresses = _localIpAddresses;
    _umsocket.requestedLocalPort = _port;
    _umsocket = [[UMSocketSCTP alloc]initWithType:UMSOCKET_TYPE_SCTP_SEQPACKET name:_name];
    if(_configuredMtu)
    {
        [_umsocket updateMtu:_configuredMtu.intValue];
    }
    if(_dscp)
    {
        [_umsocket setDscpString:_dscp];
    }
    [self setBufferSizes];
    [_umsocket switchToNonBlocking];
#define     LOG_MINOR_ERROR(err,area)  if(err) { [self logMinorError:[NSString stringWithFormat:@"ERROR in %@: %d %@",area,err,[UMSocket getSocketErrorString:err]]]; }
#define     LOG_MAYOR_ERROR(err,area)  if(err) { [self logMajorError:[NSString stringWithFormat:@"ERROR in %@: %d %@",area,err,[UMSocket getSocketErrorString:err]]]; }

    UMSocketError err = [_umsocket setNoDelay];
    LOG_MINOR_ERROR(err,@"setNoDelay");

    err = [_umsocket setInitParams];
    LOG_MINOR_ERROR(err,@"setInitParams");
    
    err = [_umsocket setIPDualStack];
    LOG_MINOR_ERROR(err,@"setIPDualStack");

    err = [_umsocket setLinger];
    LOG_MINOR_ERROR(err,@"setLinger");

    err = [_umsocket setReuseAddr];
    LOG_MINOR_ERROR(err,@"setReuseAddr");

    if(_umsocket.socketType != SOCK_SEQPACKET)
    {
        err = [_umsocket setReusePort];
        LOG_MINOR_ERROR(err,@"setReusePort");
    }

    err = [_umsocket enableEvents];
    LOG_MAYOR_ERROR(err,@"enableEvents");

    err = [_umsocket bind];
    LOG_MAYOR_ERROR(err,@"bind");
    _isBound = YES;
    if(err==UMSocketError_no_error)
    {
        err = [_umsocket listen:128];
        LOG_MAYOR_ERROR(err,@"listen");

        if(err!=UMSocketError_no_error)
        {
            _isListening = YES;
            err =[_umsocket setHeartbeat:YES];
            LOG_MINOR_ERROR(err,@"setHeartbeat");
        }
    }
    [super backgroundInit];
}


- (void)backgroundExit
{
    [_umsocket close];
    _umsocket = NULL;
    [super backgroundExit];

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

- (void)setBufferSizes
{
    int currentSize = [_umsocket receiveBufferSize];
    if(currentSize < _minReceiveBufferSize)
    {
        [_umsocket setReceiveBufferSize:_minReceiveBufferSize];
    }
    currentSize = [_umsocket sendBufferSize];
    if(currentSize < _minSendBufferSize)
    {
        [_umsocket setSendBufferSize:_minSendBufferSize];
    }
}

- (void)processReceivedData:(UMSocketSCTPReceivedPacket *)rx
{
    if(rx.err == UMSocketError_no_error)
    {
        BOOL processed=NO;
        if(rx.assocId != NULL)
        {
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
                UMLayerSctp *layer = [_registry layerForLocalIp:ip
                                                      localPort:_port
                                                       remoteIp:rx.remoteAddress
                                                     remotePort:rx.remotePort
                                                   encapsulated:NO];
                if(layer)
                {
                    if(rx.assocId)
                    {
                        [_registry registerAssoc:rx.assocId forLayer:layer];
                        if(layer.assocId==NULL)
                        {
                            layer.assocId = rx.assocId;
                        }
                        else if(layer.assocId.unsignedIntValue != rx.assocId.unsignedIntValue)
                        {
                            [self logMajorError:[NSString stringWithFormat:@"layer %@ is disagreeing on the assocId for this connection(rx %@, layer %@)",layer.layerName,rx.assocId,layer.assocId]];
                            layer.assocId = rx.assocId;
                        }
                    }
                    [layer processReceivedData:rx];
                    processed=YES;
                    break;
                }
                else
                {
                    [self logMinorError:[NSString stringWithFormat:@"layer not found for assoc=%@ local-ip=%@ local-port=%d remote-ip=%@ remote-port=%d",rx.assocId,
                                         [_localIpAddresses componentsJoinedByString:@","],_port,rx.remoteAddress,rx.remotePort]];

                }
            }
        }
        if((processed==NO) && (_sendAborts))
        {
            UMSocketError err = [_umsocket abortToAddress:rx.remoteAddress
                                                     port:rx.remotePort
                                                    assoc:rx.assocId
                                                   stream:rx.streamId
                                                 protocol:rx.protocolId];
            [self logMinorError:[NSString stringWithFormat:@"sendAbort returns error %d %@",err,[UMSocket getSocketErrorString:err]]];
        }
    }
}



- (void) processError:(UMSocketError)err
{
    [self logMajorError:[NSString stringWithFormat:@"processError %d %@",err,[UMSocket getSocketErrorString:err]]];
}

- (void) processHangup
{
    [self logMinorError:@"processHangup"];

}

- (void) processInvalidValue
{
    [self logMajorError:@"processInvalidValue"];
}

- (UMSocketError) connectToAddresses:(NSArray *)addrs
                                port:(int)port
                            assocPtr:(NSNumber **)assocptr
                               layer:(UMLayerSctp *)layer
{

    if(_isListening==NO)
    {
        [self startBackgroundTask];
    }
    [layer.layerHistory addLogEntry:[NSString stringWithFormat:@"calling sctp_connectx(%@:%d)",[addrs componentsJoinedByString:@","],port]];
    UMSocketError err = [_umsocket connectToAddresses:addrs
                                                 port:port
                                             assocPtr:assocptr
                                                layer:layer];
    if(assocptr)
    {
        if(_logLevel == UMLOG_DEBUG)
        {
            NSLog(@"   returns assoc=%@",*assocptr);
        }
    }
    [layer.layerHistory addLogEntry:[NSString stringWithFormat:@"  returns err=%d (%@), assoc=%@",err,[UMSocket getSocketErrorString:err],*assocptr]];
    return err;
}

- (ssize_t) sendToAddresses:(NSArray *)addrs
                       port:(int)remotePort
                   assocPtr:(NSNumber **)assocptr
                       data:(NSData *)data
                     stream:(NSNumber *)streamId
                   protocol:(NSNumber *)protocolId
                      error:(UMSocketError *)err2
                      layer:(UMLayerSctp *)layer
{
    ssize_t r = -1;
    if((_isListening==NO) ||  (layer.status != UMSOCKET_STATUS_OFF))
    {
        [_umsocket connectToAddresses:addrs
                                 port:remotePort
                             assocPtr:assocptr
                                layer:layer];
    }
    r = [_umsocket sendToAddresses:addrs
                              port:remotePort
                          assocPtr:assocptr
                              data:data
                            stream:streamId
                          protocol:protocolId
                             error:err2];
    return r;
}

- (NSString *)description
{
    NSMutableString *s = [[NSMutableString alloc]init];
    [s appendFormat:@"UMSocketListener2 %@ (%@:%d)",_name,[_localIpAddresses componentsJoinedByString:@","], _port];
    return s;
}

- (UMSocketSCTPReceivedPacket *)receiveSCTP
{
    return [_umsocket receiveSCTP];
}

- (void)setMtu:(int)mtu
{
    [_umsocket updateMtu:mtu];
}

- (int)mtu
{
    return [_umsocket currentMtu];
}


- (void)startListeningFor:(UMLayerSctp *)layer
{
    [_lock lock];
    if(_layers.count==0)
    {
        [self startBackgroundTask];
        [_registry addListener:self];
    }
    _layers[layer.layerName] = layer;
    [_lock unlock];
}

- (void)stopListeningFor:(UMLayerSctp *)layer
{
    [_lock lock];
    [_layers removeObjectForKey:layer.layerName];
    if(_layers.count==0)
    {
        [_registry removeListener:layer.listener];
        [self shutdownBackgroundTask];
    }
    [_lock unlock];
}

@end