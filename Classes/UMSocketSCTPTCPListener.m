//
//  UMSocketSCTPTCPListener.m
//  ulibsctp
//
//  Created by Andreas Fink on 14.12.20.
//  Copyright © 2020 Andreas Fink (andreas@fink.org). All rights reserved.
//
#if 0
#import "UMSocketSCTPTCPListener.h"
#import "UMSocketSCTP.h"
#import "UMLayerSctp.h"
#import "UMSocketSCTPRegistry.h"
#import "UMSctpOverTcp.h"

#define _umsocket _dummy

@implementation UMSocketSCTPTCPListener

- (void)startListeningFor:(UMLayerSctp *)layer
{
    [_lock lock];
    if(_isListening)
    {
        _layers[layer.layerName] =layer;
        _listeningCount = _layers.count;
    }
    else
    {
        NSAssert(_umsocketEncapsulated == NULL,@"calling startListening with _umsocketEncapsulated already existing");

        _umsocketEncapsulated = [[UMSocket alloc]initWithType:UMSOCKET_TYPE_TCP name:_name];
        _umsocketEncapsulated.localHost = [[UMHost alloc]initWithLocalhost];
        _umsocketEncapsulated.requestedLocalPort = _port;
        [_umsocketEncapsulated switchToNonBlocking];
        UMSocketError err = [_umsocketEncapsulated setIPDualStack];
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
        [_registry removeListener:self];
        [_umsocketEncapsulated close];
        _umsocketEncapsulated=NULL;
        _listeningCount = 0;
    }
    [_lock unlock];
}

- (void)dealloc
{
    [_umsocketEncapsulated close];
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
        if(processed==NO)
        {
            [_umsocketEncapsulated close];
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
    return UMSocketError_no_error;
}

- (UMSocketSCTP *) peelOffAssoc:(uint32_t)assoc error:(UMSocketError *)errptr
{
    /* tcp can't peeloff */
    return NULL;
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
    if(![_umsocketEncapsulated isConnected])
    {
        NSString *s = [NSString stringWithFormat:@"%@:  can not send. socket is not connected",_name];
        [self logMinorError:s];
        return -1;
    }
    
    sctp_over_tcp_header header;
    memset(&header,0x00,sizeof(header));
    header.header_length = htonl(sizeof(header));
    header.payload_length = htonl(data.length);
    header.protocolId = htonl(protocolId);
    header.streamId = htons(streamId);
    header.flags = 0;
    NSMutableData *d = [[NSMutableData alloc]initWithBytes:&header length:sizeof(header)];
    [d appendData:data];
    UMSocketError r = [_umsocketEncapsulated sendData:data];
    if(err2)
    {
        *err2 = r;
    }
    if(r==UMSocketError_no_error)
    {
        return d.length;
    }
    return -1;
}

@end
#endif
