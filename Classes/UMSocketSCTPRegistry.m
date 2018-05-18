//
//  UMSocketSCTPRegistry.m
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPRegistry.h"
#import "UMSocketSCTPListener.h"

@implementation UMSocketSCTPRegistry

- (UMSocketSCTPRegistry *)init
{
    self = [super init];
    if(self)
    {
        _entries = [[NSMutableDictionary alloc]init];
        _assocs = [[NSMutableDictionary alloc]init];
        _lock = [[UMMutex alloc]init];
    }
    return self;
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
        _entries[key]=e;
    }
    [_lock unlock];
    return e;
}

- (UMLayerSctp *)layerForAssoc:(NSNumber *)assocId
{
    [_lock lock];
    UMLayerSctp *sctp = _assocs[assocId];
    [_lock unlock];
    return sctp;
}

- (void)registerLayer:(UMLayerSctp *)sctp forAssoc:(NSNumber *)assocId;
{
    if(sctp && assocId)
    {
        [_lock lock];
        _assocs[assocId] = sctp;
        [_lock unlock];
    }
}

@end
