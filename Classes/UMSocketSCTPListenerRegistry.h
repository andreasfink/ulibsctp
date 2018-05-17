//
//  UMSocketSCTPListenerRegistry.h
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
@class UMSocketSCTPListener;

@interface UMSocketSCTPListenerRegistry : UMObject
{
    NSMutableDictionary *_entries;
    UMMutex *_lock;
}

+ (NSString *)keyForPort:(int)port ips:(NSArray<NSString *> *)ips;
- (UMSocketSCTPListener *)listenerForPort:(int)port localIps:(NSArray *)ips;

@end
