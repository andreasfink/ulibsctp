//
//  UMSocketSCTPListenerRegistry.m
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPListenerRegistry.h"
#import "UMSocketSCTPListener.h"

@implementation UMSocketSCTPListenerRegistry

- (UMSocketSCTPListenerRegistry *)init
{
    self = [super init];
    if(self)
    {
        _entries = [[NSMutableDictionary alloc]init];
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
    NSString *key = [UMSocketSCTPListenerRegistry keyForPort:port  ips:ips];
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

@end
