//
//  UMSocketSCTPRegistry.m
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPRegistry.h"
#import "UMSocketSCTPListener.h"
#import "UMSocketSCTPReceiver.h"
#import "UMLayerSctp.h"

@implementation UMSocketSCTPRegistry

- (UMSocketSCTPRegistry *)init
{
    self = [super init];
    if(self)
    {
        _entries = [[NSMutableDictionary alloc]init];
        _assocs = [[NSMutableDictionary alloc]init];
        _lock = [[UMMutex alloc]init];
        _receiver = [[UMSocketSCTPReceiver alloc]initWithRegistry:self];
        
        _outgoingLayers = [[NSMutableArray alloc]init];
        _incomingListeners = [[NSMutableArray alloc]init];
        _outgoingLayersByIpsAndPorts = [[NSMutableDictionary alloc]init];
        _outgoingLayersByAssoc = [[NSMutableDictionary alloc]init];
    }
    return self;
}

- (NSArray *)allListeners
{
    [_lock lock];
    NSArray *a = [_incomingListeners copy];
    [_lock unlock];
    return a;
}

- (NSArray *)allOutboundLayers
{
    [_lock lock];
    NSArray *a = [_outgoingLayers copy];
    [_lock unlock];
    return a;
}


+ (NSString *)keyForPort:(int)port ips:(NSArray<NSString *> *)ips
{
    NSArray *sortedIps = [ips sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString *s = [[NSMutableString alloc]init];
    [s appendFormat:@"%d",port];
    for(NSString *addr in sortedIps)
    {
        [s appendFormat:@",%@",addr];
    }
    return s;
}

- (UMSocketSCTPListener *)listenerForPort:(int)port localIps:(NSArray *)ips;
{
    NSString *key = [UMSocketSCTPRegistry keyForPort:port  ips:ips];
    [_lock lock];
    UMSocketSCTPListener *e = _entries[key];
    if(e == NULL)
    {
        e = [[UMSocketSCTPListener alloc]initWithPort:port localIpAddresses:ips];
        e.registry = self;
        _entries[key]=e;
        [_incomingListeners addObject:e];
    }
    [_lock unlock];
    return e;
}


- (NSString *)description
{
    NSMutableString *s = [[NSMutableString alloc]init];
    [s appendFormat:@"-----------------------------------------------------------\n"];
    [s appendFormat:@"UMSocketSCTPRegistry %p\n",self];
    NSArray *arr = _entries.allKeys;

    [s appendFormat:@".entries: %d entries]\n",(int)arr.count];
    for(NSString *key in arr)
    {
        [s appendFormat:@"  [%@]\n",key];
    }

    arr = _assocs.allKeys;
    [s appendFormat:@".assoc: %d entries]\n",(int)arr.count];
    for(NSString *key in arr)
    {
        [s appendFormat:@"  [%@]\n",key];
    }

    [s appendFormat:@".outgoingLayers: %d entries]\n",(int)_outgoingLayers.count];
    for(UMLayerSctp *layer in _outgoingLayers)
    {
        [s appendFormat:@"  [%@]\n",layer.layerName];
    }

    [s appendFormat:@".incomingListeners: %d entries]\n",(int)_incomingListeners.count];
    for(UMSocketSCTPListener *listener in _incomingListeners)
    {
        [s appendFormat:@"  [%@]\n",listener.name];
    }

    [s appendFormat:@".outgoingLayersByIpsAndPorts: %d entries]\n",(int)_outgoingLayersByIpsAndPorts.count];
    arr = _outgoingLayersByIpsAndPorts.allKeys;
    for(NSString *key in arr)
    {
        [s appendFormat:@"  [%@]\n",key];
    }


    [s appendFormat:@".outgoingLayersByAssoc: %d entries]\n",(int)_outgoingLayersByAssoc.count];
    arr = _outgoingLayersByAssoc.allKeys;
    for(NSNumber *key in arr)
    {
        [s appendFormat:@"  [%@]\n",key];
    }
    [s appendFormat:@"-----------------------------------------------------------\n"];
    return s;
}

- (void)unregisterListener:(UMSocketSCTPListener *)e
{
    [_lock lock];
    NSString *key = [UMSocketSCTPRegistry keyForPort:e.port  ips:e.localIps];
    [_entries removeObjectForKey:key];
    [_incomingListeners removeObject:e];
    [_lock unlock];
}


- (UMLayerSctp *)layerForAssoc:(NSNumber *)assocId
{
    [_lock lock];
    UMLayerSctp *sctp = _outgoingLayersByAssoc[assocId];
    [_lock unlock];
    return sctp;
}

- (UMLayerSctp *)layerForLocalIp:(NSString *)ip1
                       localPort:(int)port1
                        remoteIp:(NSString *)ip2
                      remotePort:(int)port2
{
    [_lock lock];
    NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d",
                     ip1,
                     port1,
                     ip2,
                     port2];
    UMLayerSctp *layer = _outgoingLayersByIpsAndPorts[key] ;
    [_lock unlock];
    return layer;
}

- (void)registerLayer:(UMLayerSctp *)layer forAssoc:(NSNumber *)assocId;
{
    if(layer)
    {

        [_lock lock];

        if(assocId)
        {
            /* an active outbound connection */
            _assocs[assocId] = layer;
        }
        /* we register every local IP / remote IP pair combination */

        NSArray *localAddrs = layer.configured_local_addresses;
        NSArray *remoteAddrs = layer.configured_remote_addresses;
        for(NSString *localAddr in localAddrs)
        {
            for(NSString *remoteAddr in remoteAddrs)
            {
                NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d",
                                 localAddr,
                                 layer.configured_local_port,
                                 remoteAddr,
                                 layer.configured_remote_port];
                _outgoingLayersByIpsAndPorts[key] = layer;
            }
        }

        [_outgoingLayers removeObject:layer];
        [_outgoingLayers addObject:layer];
        [_lock unlock];
    }
}

- (void)unregisterLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        [_lock lock];
        if(layer.sctpSocket.assocId)
        {
            [_assocs removeObjectForKey:layer.sctpSocket.assocId];
        }
        /* we unregister every local IP / remote IP pair combination */
        
        NSArray *localAddrs = layer.configured_local_addresses;
        NSArray *remoteAddrs = layer.configured_remote_addresses;
        for(NSString *localAddr in localAddrs)
        {
            for(NSString *remoteAddr in remoteAddrs)
            {
                NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d",
                                 localAddr,
                                 layer.configured_local_port,
                                 remoteAddr,
                                 layer.configured_remote_port];
                
                [_outgoingLayersByIpsAndPorts removeObjectForKey:key];
            }
        }
        [_outgoingLayers removeObject:layer];
        [_lock unlock];
    }
}

- (void)startReceiver
{
    if(_receiverStarted==YES)
    {
        return;
    }
    [_lock lock];
    if(_receiverStarted==NO)
    {
        [_receiver startBackgroundTask];
        _receiverStarted = YES;
    }
    [_lock unlock];

}

- (void)stopReceiver
{
    [_lock lock];
    if(_receiverStarted==YES)
    {
        [_receiver shutdownBackgroundTask];
        _receiverStarted=NO;
    }
    [_lock unlock];
}
@end
