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
        _lock = [[UMMutex alloc]initWithName:@"umsocket-sctp-registry"];
        _receiver = [[UMSocketSCTPReceiver alloc]initWithRegistry:self];
        _outgoingLayers = [[NSMutableArray alloc]init];
        _incomingListeners = [[NSMutableArray alloc]init];
        _outgoingLayersByIpsAndPorts = [[NSMutableDictionary alloc]init];
        _outgoingLayersByAssoc = [[NSMutableDictionary alloc]init];
        _logLevel = UMLOG_MINOR;

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

/*
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
*/

+ (NSString *)keyForPort:(int)port ip:(NSString *)addr
{
    return [NSString stringWithFormat:@"%d,%@",port,addr];
}

- (UMSocketSCTPListener *)getOrAddListenerForPort:(int)port localIps:(NSArray<NSString *> *)ips
{
    [_lock lock];
    UMSocketSCTPListener *listener = [self getListenerForPort:port localIps:ips];

    if(listener == NULL)
    {
        listener = [[UMSocketSCTPListener alloc]initWithPort:port localIpAddresses:ips];
        listener.logLevel = _logLevel;
        listener.sendAborts = _sendAborts;
        [self addListener:listener];
    }
    [_lock unlock];
    return listener;
}

- (UMSocketSCTPListener *)getListenerForPort:(int)port localIps:(NSArray<NSString *> *)ips
{
    NSArray *ips2 = [ips sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *s = [ips2 componentsJoinedByString:@","];
    return [self getListenerForPort:port localIp:s];
}


- (UMSocketSCTPListener *)getListenerForPort:(int)port localIp:(NSString *)ip
{
    UMSocketSCTPListener *e = NULL;
    [_lock lock];
    NSString *key =[UMSocketSCTPRegistry keyForPort:port ip:ip];
    e = _entries[key];
    [_lock unlock];
    return e;
}

- (void)addListener:(UMSocketSCTPListener *)listener
{
    for(NSString *ip in listener.localIpAddresses)
    {
        [self addListener:listener forPort:listener.port localIp:ip];
    }
    NSArray *ips2 = [listener.localIpAddresses sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *s = [ips2 componentsJoinedByString:@","];
    [self addListener:listener forPort:listener.port localIp:s];
}

- (void)addListener:(UMSocketSCTPListener *)listener forPort:(int)port localIp:(NSString *)ip
{
    [_lock lock];
    listener.registry = self;
    NSString *key =[UMSocketSCTPRegistry keyForPort:port ip:ip];
    _entries[key]=listener;
    [_incomingListeners removeObject:listener]; /* has to be added only once */
    [_incomingListeners addObject:listener];
    [_lock unlock];
}


- (void)removeListener:(UMSocketSCTPListener *)listener
{
    for(NSString *ip in listener.localIpAddresses)
    {
        [self removeListener:listener forPort:listener.port localIp:ip];
    }
    NSArray *ips2 = [listener.localIpAddresses sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *s = [ips2 componentsJoinedByString:@","];
    [self removeListener:listener forPort:listener.port localIp:s];
}

- (void)removeListener:(UMSocketSCTPListener *)listener forPort:(int)port localIp:(NSString *)ip
{
    [_lock lock];
    listener.registry = NULL;
    NSString *key =[UMSocketSCTPRegistry keyForPort:port ip:ip];
    [_entries removeObjectForKey:key];
    [_incomingListeners removeObject:listener];
    [_lock unlock];
}


#if 0
- (UMSocketSCTPListener *)listenerForPort:(int)port localIps:(NSArray *)ips;
{
    [_lock lock];

    NSString *key1 =[UMSocketSCTPRegistry keyForPort:port ips:ips];
    UMSocketSCTPListener *e = _entries[key1];
    if(e == NULL)
    {
        for(NSString *ip in ips)
        {
            NSString *key2 =[UMSocketSCTPRegistry keyForPort:port ip:ip];
            e = _entries[key2];
            if(e)
            {
                break;
            }
        }
        if(e==NULL)
        {
            e = [[UMSocketSCTPListener alloc]initWithPort:port localIpAddresses:ips];
            e.sendAborts = _sendAborts;
            e.registry = self;
            NSString *key1 =[UMSocketSCTPRegistry keyForPort:port ips:ips];
            _entries[key1]=e;
            for(NSString *ip in ips)
            {
                NSString *key2 =[UMSocketSCTPRegistry keyForPort:port ip:ip];
                _entries[key2]=e;
            }
            [_incomingListeners addObject:e];
        }
    }
    [_lock unlock];
    return e;
}
#endif

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

#if 0
- (void)unregisterListener:(UMSocketSCTPListener *)e
{
    [_lock lock];
    NSString *key1 = [UMSocketSCTPRegistry keyForPort:e.port  ips:e.localIpAddresses];
    [_entries removeObjectForKey:key1];
    for(NSString *ip in e.localIpAddresses)
    {
        NSString *key2 = [UMSocketSCTPRegistry keyForPort:e.port  ip:ip];
        [_entries removeObjectForKey:key2];
    }
    [_incomingListeners removeObject:e];
    [_lock unlock];
}
#endif


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
    //NSLog(@"layerForLocalIp:%@ localPort:%d remoteIp:%@ remotePort:%d",ip1,port1,ip2,port2);
    [_lock lock];
    NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d",
                     ip1,
                     port1,
                     ip2,
                     port2];
    //NSLog(@" key=%@",key);
    UMLayerSctp *layer = _outgoingLayersByIpsAndPorts[key] ;
    if(layer==NULL)
    {
        NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d",
                         ip1,
                         port1,
                         ip2,
                         0];
        layer = _outgoingLayersByIpsAndPorts[key] ;
    }
    [_lock unlock];
    //NSLog(@" layer=%@",layer.layerName);
    return layer;
}

- (void)registerIncomingLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        [_lock lock];
        [_incomingLayers removeObject:layer];
        [_incomingLayers addObject:layer];
        [_lock unlock];
    }
}

- (void)registerOutgoingLayer:(UMLayerSctp *)layer
{
    [self registerOutgoingLayer:layer allowAnyRemotePortIncoming:NO];

}

- (void)registerOutgoingLayer:(UMLayerSctp *)layer allowAnyRemotePortIncoming:(BOOL)anyPort
{
    if(layer)
    {
        [_lock lock];

        /* we register every local IP / remote IP pair combination */

        NSArray *localAddrs = layer.configured_local_addresses;
        NSArray *remoteAddrs = layer.configured_remote_addresses;
        for(NSString *localAddr in localAddrs)
        {
            for(NSString *remoteAddr in remoteAddrs)
            {
                NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d(%@)",
                                 localAddr,
                                 layer.configured_local_port,
                                 remoteAddr,
                                 layer.configured_remote_port,
                                 (layer.encapsulatedOverTcp? @"tcp" : @"sctp")];
                _outgoingLayersByIpsAndPorts[key] = layer;
                if(anyPort)
                {
                    NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d(%@)",
                                     localAddr,
                                     layer.configured_local_port,
                                     remoteAddr,
                                     0,
                                     (layer.encapsulatedOverTcp ? @"tcp" : @"sctp")];
                    _outgoingLayersByIpsAndPorts[key] = layer;
                }
            }
        }
        [_outgoingLayers removeObject:layer];
        [_outgoingLayers addObject:layer];
        [_lock unlock];
    }
}

- (void)registerAssoc:(NSNumber *)assocId forLayer:(UMLayerSctp *)layer
{
    [_lock lock];

    UMAssert(layer,@"layer is NULL");
    if(assocId)
    {
        /* an active outbound connection */
        NSLog(@"registerAssoc %@ forLayer:%@",assocId,layer.layerName);
        _assocs[assocId] = layer;
    }
    [_lock unlock];

}

- (void)unregisterAssoc:(NSNumber *)assocId
{
    [_lock lock];
    if(assocId)
    {
        UMLayerSctp *layer = _assocs[assocId];
        /* an active outbound connection */
        NSLog(@"unregisterAssoc %@ forLayer:%@",assocId,layer.layerName);
        [_assocs removeObjectForKey:assocId];
    }
    [_lock unlock];
}


- (void)unregisterLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        [_lock lock];
        if(layer.assocIdPresent)
        {
            [_assocs removeObjectForKey:@(layer.assocId)];
        }
        /* we unregister every local IP / remote IP pair combination */
        
        NSArray *localAddrs = layer.configured_local_addresses;
        NSArray *remoteAddrs = layer.configured_remote_addresses;
        for(NSString *localAddr in localAddrs)
        {
            for(NSString *remoteAddr in remoteAddrs)
            {
                NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d(%@)",
                                 localAddr,
                                 layer.configured_local_port,
                                 remoteAddr,
                                 layer.configured_remote_port,
                                 (layer.encapsulatedOverTcp ? @"tcp" : @"sctp")];
                [_outgoingLayersByIpsAndPorts removeObjectForKey:key];
            }
        }
        [_outgoingLayers removeObject:layer];
        [_incomingLayers removeObject:layer];
        [_lock unlock];
    }
}

- (void)startReceiver
{
    if(_logLevel <= UMLOG_DEBUG)
    {
        [_logFeed debugText:@"[UMSocketSCTPegistry startReceiver]"];
    }
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
    if(_logLevel <= UMLOG_DEBUG)
    {
        [_logFeed debugText:@"[UMSocketSCTPegistry stopReceiver]"];
    }

    [_lock lock];
    if(_receiverStarted==YES)
    {
        [_receiver shutdownBackgroundTask];
        _receiverStarted=NO;
    }
    [_lock unlock];
}

- (NSString *)webStat
{
    NSMutableString *s = [[NSMutableString alloc]init];
    [_lock lock];
    [s appendString:@"<html>\n"];
    [s appendString:@"<header>\n"];
    [s appendString:@"    <link rel=\"stylesheet\" href=\"/css/style.css\" type=\"text/css\">\n"];
    [s appendFormat:@"    <title>Debug: SCTP Registry Statistic</title>\n"];
    [s appendString:@"</header>\n"];
    [s appendString:@"<body>\n"];

    [s appendString:@"<h2>Debug: SCTP Registry Statistic</h2>\n"];
    [s appendString:@"<UL>\n"];
    [s appendString:@"<LI><a href=\"/\">main</a></LI>\n"];
    [s appendString:@"<LI><a href=\"/debug\">debug</a></LI>\n"];
    [s appendString:@"</UL>\n"];

    [s appendString:@"<table class=\"object_table\">\n"];
    [s appendString:@"    <tr>\r\n"];
    [s appendString:@"        <th class=\"object_title\">Object Type</th>\r\n"];
    [s appendString:@"        <th class=\"object_title\">Count</th>\r\n"];
    [s appendString:@"    </tr>\r\n"];

    [s appendString:@"    <tr>\r\n"];
    [s appendFormat:@"        <td class=\"object_name\">_entries</td>\r\n"];
    [s appendFormat:@"        <td class=\"object_value\">%d</th>\r\n",(int)_entries.count];
    [s appendString:@"    </tr>\r\n"];

    [s appendString:@"    <tr>\r\n"];
    [s appendFormat:@"        <td class=\"object_name\">_assocs</td>\r\n"];
    [s appendFormat:@"        <td class=\"object_value\">%d</th>\r\n",(int)_assocs.count];
    [s appendString:@"    </tr>\r\n"];

    [s appendString:@"    <tr>\r\n"];
    [s appendFormat:@"        <td class=\"object_name\">_outgoingLayers</td>\r\n"];
    [s appendFormat:@"        <td class=\"object_value\">%d</th>\r\n",(int)_outgoingLayers.count];
    [s appendString:@"    </tr>\r\n"];

    [s appendString:@"    <tr>\r\n"];
    [s appendFormat:@"        <td class=\"object_name\">_incomingListeners</td>\r\n"];
    [s appendFormat:@"        <td class=\"object_value\">%d</th>\r\n",(int)_incomingListeners.count];
    [s appendString:@"    </tr>\r\n"];

    [s appendString:@"    <tr>\r\n"];
    [s appendFormat:@"        <td class=\"object_name\">_outgoingLayersByIpsAndPorts</td>\r\n"];
    [s appendFormat:@"        <td class=\"object_value\">%d</th>\r\n",(int)_outgoingLayersByIpsAndPorts.count];
    [s appendString:@"    </tr>\r\n"];
    [s appendString:@"</table>\r\n"];
    [s appendString:@"</body>\r\n"];
    [s appendString:@"</html>\r\n"];
    [_lock unlock];
    return s;
}
@end
