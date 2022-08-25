//
//  UMSocketSCTPRegistry.m
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPRegistry.h"

#ifdef USE_LISTENER1
#import "UMSocketSCTPListener.h"
#import "UMSocketSCTPReceiver.h"
#else
#import "UMSocketSCTPListener2.h"
#endif

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
#if USE_LISTENER1
        _receiver = [[UMSocketSCTPReceiver alloc]initWithRegistry:self];
#endif
        _outgoingLayers = [[NSMutableArray alloc]init];
        _incomingLayers = [[NSMutableArray alloc]init];
        _outgoingTcpLayers = [[NSMutableArray alloc]init];
        _incomingTcpLayers = [[NSMutableArray alloc]init];
        _incomingListeners = [[NSMutableArray alloc]init];
        _incomingTcpListeners = [[NSMutableDictionary alloc] init];
        _outgoingLayersByIpsAndPorts = [[NSMutableDictionary alloc]init];
        _outgoingLayersByAssoc = [[NSMutableDictionary alloc]init];
        _layersBySessionKey = [[NSMutableDictionary alloc]init];
        _logLevel = UMLOG_MINOR;

    }
    return self;
}

- (NSArray *)allListeners
{
    NSArray *a = NULL;
    UMMUTEX_LOCK(_lock);
    a = [_incomingListeners copy];
    UMMUTEX_UNLOCK(_lock);
    return a;
}

- (NSArray *)allTcpListeners
{
    UMMUTEX_LOCK(_lock);
    NSMutableDictionary *dict =  [_incomingTcpListeners copy];
    NSMutableArray *a = [[NSMutableArray alloc]init];
    for(id k in dict.allKeys)
    {
        [a addObject:dict[k]];
    }
    UMMUTEX_UNLOCK(_lock);
    return a;
}


- (NSArray *)allOutboundLayers
{
    UMMUTEX_LOCK(_lock);
    NSArray *a = [_outgoingLayers copy];
    UMMUTEX_UNLOCK(_lock);
    return a;
}

- (NSArray *)allInboundLayers
{
    UMMUTEX_LOCK(_lock);
    NSArray *a = [_incomingLayers copy];
    UMMUTEX_UNLOCK(_lock);
    return a;
}

- (NSArray *)allOutboundTcpLayers
{
    UMMUTEX_LOCK(_lock);
    NSArray *a = [_outgoingTcpLayers copy];
    UMMUTEX_UNLOCK(_lock);
    return a;
}

- (NSArray *)allInboundTcpLayers
{
    UMMUTEX_LOCK(_lock);
    NSArray *a = [_incomingTcpLayers copy];
    UMMUTEX_UNLOCK(_lock);
    return a;
}


+ (NSString *)keyForPort:(int)port ip:(NSString *)addr
{
    return [NSString stringWithFormat:@"%d,%@",port,addr];
}

#ifdef USE_LISTENER1
- (UMSocketSCTPListener *)getOrAddListenerForPort:(int)port localIps:(NSArray<NSString *> *)ips
#else
- (UMSocketSCTPListener2 *)getOrAddListenerForPort:(int)port localIps:(NSArray<NSString *> *)ips
#endif

{
#ifdef USE_LISTENER1
    UMSocketSCTPListener *listener = NULL;
#else
    UMSocketSCTPListener2 *listener = NULL;
#endif
    UMMUTEX_LOCK(_lock);
    @try
    {
        listener = [self getListenerForPort:port localIps:ips];

        if(listener == NULL)
        {
#ifdef USE_LISTENER1
            listener = [[UMSocketSCTPListener alloc]initWithPort:port localIpAddresses:ips];
#else
            listener = [[UMSocketSCTPListener2 alloc]initWithPort:port localIpAddresses:ips];
#endif
            listener.logLevel = _logLevel;
            listener.sendAborts = _sendAborts;
            [self addListener:listener];
        }
    }
    @catch(NSException *e)
    {
        [self handleException:e];
    }
    @finally
    {
        UMMUTEX_UNLOCK(_lock);
    }
    return listener;
}

#ifdef USE_LISTENER1
- (UMSocketSCTPListener *)getListenerForPort:(int)port localIps:(NSArray<NSString *> *)ips
#else
- (UMSocketSCTPListener2 *)getListenerForPort:(int)port localIps:(NSArray<NSString *> *)ips
#endif
{
    NSArray *ips2 = [ips sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *s = [ips2 componentsJoinedByString:@","];
    return [self getListenerForPort:port localIp:s];
}


#ifdef USE_LISTENER1
- (UMSocketSCTPListener *)getListenerForPort:(int)port localIp:(NSString *)ip
#else
- (UMSocketSCTPListener2 *)getListenerForPort:(int)port localIp:(NSString *)ip
#endif
{
    UMMUTEX_LOCK(_lock);
    NSString *key =[UMSocketSCTPRegistry keyForPort:port ip:ip];
#ifdef USE_LISTENER1
    UMSocketSCTPListener *e = _entries[key];
#else
    UMSocketSCTPListener2 *e = _entries[key];
#endif
    UMMUTEX_UNLOCK(_lock);
    return e;
}

#ifdef USE_LISTENER1
- (void)addListener:(UMSocketSCTPListener *)listener
#else
- (void)addListener:(UMSocketSCTPListener2 *)listener
#endif
{
    for(NSString *ip in listener.localIpAddresses)
    {
        [self addListener:listener forPort:listener.port localIp:ip];
    }
    NSArray *ips2 = [listener.localIpAddresses sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *s = [ips2 componentsJoinedByString:@","];
    [self addListener:listener forPort:listener.port localIp:s];
}


#ifdef USE_LISTENER1
- (void)addListener:(UMSocketSCTPListener *)listener forPort:(int)port localIp:(NSString *)ip
#else
- (void)addListener:(UMSocketSCTPListener2 *)listener forPort:(int)port localIp:(NSString *)ip
#endif
{
    if(listener.tcpEncapsulated)
    {
        [self addTcpListener:listener];
        return;
    }

    UMMUTEX_LOCK(_lock);
    listener.registry = self;
    NSString *key =[UMSocketSCTPRegistry keyForPort:port ip:ip];
    _entries[key]=listener;
    [_incomingListeners removeObject:listener]; /* has to be added only once */
    [_incomingListeners addObject:listener];
    UMMUTEX_UNLOCK(_lock);
}


#ifdef USE_LISTENER1
- (void)removeListener:(UMSocketSCTPListener *)listener
#else
- (void)removeListener:(UMSocketSCTPListener2 *)listener
#endif
{
    for(NSString *ip in listener.localIpAddresses)
    {
        [self removeListener:listener forPort:listener.port localIp:ip];
    }
    NSArray *ips2 = [listener.localIpAddresses sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSString *s = [ips2 componentsJoinedByString:@","];
    [self removeListener:listener forPort:listener.port localIp:s];
}

#ifdef USE_LISTENER1
- (void)removeListener:(UMSocketSCTPListener *)listener forPort:(int)port localIp:(NSString *)ip
#else
- (void)removeListener:(UMSocketSCTPListener2 *)listener forPort:(int)port localIp:(NSString *)ip
#endif
{
    UMMUTEX_LOCK(_lock);
    listener.registry = NULL;
    NSString *key =[UMSocketSCTPRegistry keyForPort:port ip:ip];
    [_entries removeObjectForKey:key];
    [_incomingListeners removeObject:listener];
    UMMUTEX_UNLOCK(_lock);
}


#ifdef USE_LISTENER1
- (UMSocketSCTPListener *)getOrAddTcpListenerForPort:(int)port
#else
- (UMSocketSCTPListener2 *)getOrAddTcpListenerForPort:(int)port
#endif
{
#ifdef USE_LISTENER1
    UMSocketSCTPListener *listener  = NULL;
#else
    UMSocketSCTPListener2 *listener  = NULL;
#endif
    UMMUTEX_LOCK(_lock);
    @try
    {
        listener = [self getTcpListenerForPort:port];
        if(listener == NULL)
        {
#ifdef USE_LISTENER1
            listener = [[UMSocketSCTPListener alloc]initWithPort:port localIpAddresses:NULL];
#else
            listener = [[UMSocketSCTPListener2 alloc]initWithPort:port localIpAddresses:NULL];
#endif
            [self addTcpListener:listener];
        }
    }
    @catch(NSException *e)
    {
        [self handleException:e];
    }
    @finally
    {
        UMMUTEX_UNLOCK(_lock);
    }
    return listener;
}

#ifdef  USE_LISTENER1
- (UMSocketSCTPListener *)getTcpListenerForPort:(int)port
#else
- (UMSocketSCTPListener2 *)getTcpListenerForPort:(int)port
#endif
{
    UMMUTEX_LOCK(_lock);
#ifdef  USE_LISTENER1
    UMSocketSCTPListener *e =  _incomingTcpListeners[@(port)];
#else
    UMSocketSCTPListener2 *e =  _incomingTcpListeners[@(port)];

#endif
    UMMUTEX_UNLOCK(_lock);
    return e;
}

#ifdef  USE_LISTENER1
- (void)addTcpListener:(UMSocketSCTPListener *)listener
#else
- (void)addTcpListener:(UMSocketSCTPListener2 *)listener
#endif
{
    UMMUTEX_LOCK(_lock);
    listener.registry = self;
    _incomingTcpListeners[@(listener.port)] = listener;
    UMMUTEX_UNLOCK(_lock);
}

#ifdef USE_LISTENER1
- (void)removeTcpListener:(UMSocketSCTPListener *)listener
#else
- (void)removeTcpListener:(UMSocketSCTPListener2 *)listener
#endif
{
    UMMUTEX_LOCK(_lock);
    listener.registry = NULL;
    [_incomingTcpListeners removeObjectForKey:@(listener.port)];
    UMMUTEX_UNLOCK(_lock);
}

- (UMSynchronizedSortedDictionary *)descriptionDict;
{
    UMSynchronizedSortedDictionary *dict = [[UMSynchronizedSortedDictionary alloc]init];

    NSMutableArray *a1 = [[NSMutableArray alloc]init];
    
    NSArray *arr = _entries.allKeys;
    for(NSString *key in arr)
    {
        [a1 addObject:key];
    }

    dict[@"entries"] = @{ @"count"   : @(arr.count),
                          @"entries" : a1,
                        };


    arr = _assocs.allKeys;
    
    a1 = [[NSMutableArray alloc]init];
    for(NSString *key in arr)
    {
        [a1 addObject:key];
    }
    dict[@"assocs"] = @{ @"count"   : @(arr.count),
                          @"assocs" : a1,
                        };

    arr = _outgoingLayers;
    a1 = [[NSMutableArray alloc]init];
    for(UMLayerSctp *layer in _outgoingLayers)
    {
        [a1 addObject:layer.layerName];
    }
    dict[@"outgoing-layers"] = @{ @"count"   : @(a1.count),
                                  @"names" : a1,
                                };

    
    a1 = [[NSMutableArray alloc]init];
#ifdef USE_LISTENER1
    for(UMSocketSCTPListener *listener in _incomingListeners)
#else
    for(UMSocketSCTPListener2 *listener in _incomingListeners)
#endif
    {
        [a1 addObject:listener.name];
    }
    dict[@"incoming-listeners"] = @{ @"count"   : @(a1.count),
                                  @"names" : a1,
                                };

    a1 = [[NSMutableArray alloc]init];
    arr = _outgoingLayersByIpsAndPorts.allKeys;
    for(NSString *key in arr)
    {
        [a1 addObject:key];
    }
    
    
    dict[@"outgoing-layers-by-ips-and-ports"] = @{ @"count"   : @(a1.count),
                                                   @"entries" : a1,
                                                };


    a1 = [[NSMutableArray alloc]init];
    arr = _outgoingLayersByAssoc.allKeys;
    for(NSNumber *key in arr)
    {
        [a1 addObject:key];
    }
    dict[@"outgoing-layers-by-assoc"] = @{ @"count"   : @(a1.count),
                                                   @"entries" : a1,
                                                };

    return dict;
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
        UMLayerSctp *xlayer = _assocs[key];
        [s appendFormat:@"  [%@] -> %@\n",key,xlayer.layerName];
    }

    [s appendFormat:@".outgoingLayers: %d entries]\n",(int)_outgoingLayers.count];
    for(UMLayerSctp *layer in _outgoingLayers)
    {
        [s appendFormat:@"  [%@]\n",layer.layerName];
    }

    [s appendFormat:@".incomingListeners: %d entries]\n",(int)_incomingListeners.count];
#ifdef USE_LISTENER1
    for(UMSocketSCTPListener *listener in _incomingListeners)
#else
    for(UMSocketSCTPListener2 *listener in _incomingListeners)
#endif
    {
        [s appendFormat:@"  [%@]\n",listener.name];
    }

    [s appendFormat:@".outgoingLayersByIpsAndPorts: %d entries]\n",(int)_outgoingLayersByIpsAndPorts.count];
    arr = _outgoingLayersByIpsAndPorts.allKeys;
    for(NSString *key in arr)
    {
        UMLayerSctp *xlayer = _outgoingLayersByIpsAndPorts[key];
        [s appendFormat:@"  [%@] -> %@\n",key,xlayer.layerName];
    }


    [s appendFormat:@".outgoingLayersByAssoc: %d entries]\n",(int)_outgoingLayersByAssoc.count];
    arr = _outgoingLayersByAssoc.allKeys;
    for(NSNumber *key in arr)
    {
        UMLayerSctp *xlayer = _outgoingLayersByAssoc[key];
        [s appendFormat:@"  [%@] -> %@\n",key,xlayer.layerName];
    }
    [s appendFormat:@"-----------------------------------------------------------\n"];
    return s;
}



- (UMLayerSctp *)layerForAssoc:(NSNumber *)assocId
{
    UMMUTEX_LOCK(_lock);
    UMLayerSctp *sctp = _assocs[assocId];
    if(sctp==NULL)
    {
        sctp = _outgoingLayersByAssoc[assocId];
    }
    UMMUTEX_UNLOCK(_lock);
    return sctp;
}

- (UMLayerSctp *)layerForLocalIp:(NSString *)ip1
                       localPort:(int)port1
                        remoteIp:(NSString *)ip2
                      remotePort:(int)port2
                    encapsulated:(BOOL)encap
{
    if(_logLevel <=UMLOG_DEBUG)
    {
        NSLog(@"layerForLocalIp:%@ localPort:%d remoteIp:%@ remotePort:%d encapsulated:%@",ip1,port1,ip2,port2,encap ? @"YES": @"NO");
    }
    UMMUTEX_LOCK(_lock);
    NSString *key = [UMSocketSCTPRegistry registryKeyForLocalAddr:ip1
                                                        localPort:port1
                                                       remoteAddr:ip2
                                                       remotePort:port2
                                                     encapsulated:encap];
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(_logLevel <=UMLOG_DEBUG)
    {
        NSLog(@" key=%@",key);
    }
#endif
    UMLayerSctp *layer = _outgoingLayersByIpsAndPorts[key] ;
    UMMUTEX_UNLOCK(_lock);

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(_logLevel <=UMLOG_DEBUG)
    {
        if(layer==NULL)
        {
            NSLog(@"  known keys: %@",[_outgoingLayersByIpsAndPorts allKeys]);
        }
    }
#endif
    return layer;
}

- (void)registerIncomingLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        UMMUTEX_LOCK(_lock);
        [_incomingLayers removeObject:layer];
        [_incomingLayers addObject:layer];
        UMMUTEX_UNLOCK(_lock);
    }
}

- (void)registerIncomingTcpLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        UMMUTEX_LOCK(_lock);
        [_incomingTcpLayers removeObject:layer];
        [_incomingTcpLayers addObject:layer];
        if(layer.encapsulatedOverTcpSessionKey)
        {
            [self registerSessionKey:layer.encapsulatedOverTcpSessionKey forLayer:layer];
        }
        UMMUTEX_UNLOCK(_lock);
    }
}

- (void)unregisterIncomingTcpLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        UMMUTEX_LOCK(_lock);
        [_incomingTcpLayers removeObject:layer];
        if(layer.encapsulatedOverTcpSessionKey)
        {
            [self unregisterSessionKey:layer.encapsulatedOverTcpSessionKey];
        }
        UMMUTEX_UNLOCK(_lock);
    }
}


- (void)registerOutgoingLayer:(UMLayerSctp *)layer
{
    [self registerOutgoingLayer:layer allowAnyRemotePortIncoming:NO];

}

- (void)registerOutgoingTcpLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        UMMUTEX_LOCK(_lock);
        [_outgoingTcpLayers removeObject:layer];
        [_outgoingTcpLayers addObject:layer];
        if(layer.encapsulatedOverTcpSessionKey)
        {
            [self registerSessionKey:layer.encapsulatedOverTcpSessionKey forLayer:layer];
        }
        UMMUTEX_UNLOCK(_lock);
    }
}

- (void)unregisterOutgoingTcpLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        UMMUTEX_LOCK(_lock);
        [_outgoingTcpLayers removeObject:layer];
        if(layer.encapsulatedOverTcpSessionKey)
        {
            [self unregisterSessionKey:layer.encapsulatedOverTcpSessionKey];
        }
        UMMUTEX_UNLOCK(_lock);
    }
}

- (void)registerOutgoingLayer:(UMLayerSctp *)layer allowAnyRemotePortIncoming:(BOOL)anyPort
{
    if(layer)
    {
        UMMUTEX_LOCK(_lock);
        @try
        {

            /* we register every local IP / remote IP pair combination */

            NSArray *localAddrs = layer.configured_local_addresses;
            NSArray *remoteAddrs = layer.configured_remote_addresses;
            for(NSString *localAddr in localAddrs)
            {
                for(NSString *remoteAddr in remoteAddrs)
                {
                    NSString *key = [UMSocketSCTPRegistry registryKeyForLocalAddr:localAddr
                                                                        localPort:layer.configured_local_port
                                                                       remoteAddr:remoteAddr
                                                                       remotePort:layer.configured_remote_port
                                                                     encapsulated:layer.encapsulatedOverTcp];
                    _outgoingLayersByIpsAndPorts[key] = layer;
                    if(anyPort)
                    {
                        NSString *key = [UMSocketSCTPRegistry registryKeyForLocalAddr:localAddr
                                                                            localPort:layer.configured_local_port
                                                                           remoteAddr:remoteAddr
                                                                           remotePort:0
                                                                         encapsulated:layer.encapsulatedOverTcp];
                        _outgoingLayersByIpsAndPorts[key] = layer;
                    }
                }
            }
            [_outgoingLayers removeObject:layer];
            [_outgoingLayers addObject:layer];
        }
        @catch(NSException *e)
        {
            [self handleException:e];
        }
        @finally
        {
            UMMUTEX_UNLOCK(_lock);
        }
    }
}

- (void)registerAssoc:(NSNumber *)assocId forLayer:(UMLayerSctp *)layer
{
    UMMUTEX_LOCK(_lock);
    UMAssert(layer,@"layer is NULL");
    if(assocId)
    {
        /* an active outbound connection */
        if(_logLevel <=UMLOG_DEBUG)
        {
            NSLog(@"registerAssoc %@ forLayer:%@",assocId,layer.layerName);
        }
        _assocs[assocId] = layer;
    }
    UMMUTEX_UNLOCK(_lock);

}

- (void)unregisterAssoc:(NSNumber *)assocId
{
    UMMUTEX_LOCK(_lock);
    if(assocId)
    {
        UMLayerSctp *layer = _assocs[assocId];
        /* an active outbound connection */
        if(_logLevel <=UMLOG_DEBUG)
        {
            NSLog(@"unregisterAssoc %@ forLayer:%@",assocId,layer.layerName);
        }
        [_assocs removeObjectForKey:assocId];
    }
    UMMUTEX_UNLOCK(_lock);
}


- (void)registerSessionKey:(NSString *)session_key forLayer:(UMLayerSctp *)layer
{
    if(layer.encapsulatedOverTcpSessionKey)
    {
        UMMUTEX_LOCK(_lock);
        _layersBySessionKey[session_key] = layer;
        UMMUTEX_UNLOCK(_lock);
    }
}

- (void)unregisterSessionKey:(NSString *)session_key
{
    UMMUTEX_LOCK(_lock);
    [_layersBySessionKey removeObjectForKey:session_key];
    UMMUTEX_UNLOCK(_lock);
}

- (void)unregisterLayer:(UMLayerSctp *)layer
{
    if(layer)
    {
        UMMUTEX_LOCK(_lock);
        @try
        {
            if(layer.assocId !=NULL)
            {
                [_assocs removeObjectForKey:layer.assocId];
            }
            /* we unregister every local IP / remote IP pair combination */
            
            NSArray *localAddrs = layer.configured_local_addresses;
            NSArray *remoteAddrs = layer.configured_remote_addresses;
            for(NSString *localAddr in localAddrs)
            {
                for(NSString *remoteAddr in remoteAddrs)
                {
                    NSString *key = [UMSocketSCTPRegistry registryKeyForLocalAddr:localAddr
                                                                        localPort:layer.configured_local_port
                                                                       remoteAddr:remoteAddr
                                                                       remotePort:layer.configured_remote_port
                                                                     encapsulated:layer.encapsulatedOverTcp];
                    [self unregisterSessionKey:key];
                }
            }
            [_outgoingLayers removeObject:layer];
            [_incomingLayers removeObject:layer];
            [_outgoingTcpLayers removeObject:layer];
            [_incomingTcpLayers removeObject:layer];
            if(layer.encapsulatedOverTcpSessionKey)
            {
                [self unregisterSessionKey:layer.encapsulatedOverTcpSessionKey];
            }
        }
        @catch(NSException *e)
        {
            [self handleException:e];
        }
        @finally
        {
            UMMUTEX_UNLOCK(_lock);
        }
    }
}

#ifdef USE_LISTENER1

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
    UMMUTEX_LOCK(_lock);
    if(_receiverStarted==NO)
    {
        [_receiver startBackgroundTask];
        _receiverStarted = YES;
    }
    UMMUTEX_UNLOCK(_lock);
}

- (void)stopReceiver
{
    if(_logLevel <= UMLOG_DEBUG)
    {
        [_logFeed debugText:@"[UMSocketSCTPegistry stopReceiver]"];
    }

    UMMUTEX_LOCK(_lock);
    if(_receiverStarted==YES)
    {
        [_receiver shutdownBackgroundTask];
        _receiverStarted=NO;
    }
    UMMUTEX_UNLOCK(_lock);
}
#endif /* USE_LISTENER1 */

- (NSString *)webStat
{
    NSMutableString *s = [[NSMutableString alloc]init];
    UMMUTEX_LOCK(_lock);
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
    UMMUTEX_UNLOCK(_lock);
    return s;
}

- (UMLayerSctp *)layerForSessionKey:(NSString *)sessionKey
{
    UMMUTEX_LOCK(_lock);
    UMLayerSctp *layer = _layersBySessionKey[sessionKey];
    UMMUTEX_UNLOCK(_lock);
    return layer;
}


+ (NSString *)registryKeyForLocalAddr:(NSString *)lo
                            localPort:(int)lp
                           remoteAddr:(NSString *)ra
                           remotePort:(int)rp
                         encapsulated:(BOOL)encap
{
    NSString *key = [NSString stringWithFormat:@"%@/%d->%@/%d(%@)",lo,lp,ra,rp,encap ? @"tcp" : @"sctp"];
    return key;
}

- (void)handleException:(NSException *)e
{
    if(_logLevel <=UMLOG_MINOR)
    {
        NSLog(@"Exception: %@",e);
    }
}

@end
    
