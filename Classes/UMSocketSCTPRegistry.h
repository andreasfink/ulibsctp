//
//  UMSocketSCTPRegistry.h
//  ulibsctp
//
//  Created by Andreas Fink on 17.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
@class UMSocketSCTPListener;
@class UMLayerSctp;

@interface UMSocketSCTPRegistry : UMObject
{
    NSMutableDictionary *_entries;
    NSMutableDictionary *_assocs;
    UMMutex *_lock;
}

+ (NSString *)keyForPort:(int)port ips:(NSArray<NSString *> *)ips;
- (UMSocketSCTPListener *)listenerForPort:(int)port localIps:(NSArray *)ips;
- (UMLayerSctp *)layerForAssoc:(NSNumber *)assocId;
- (void)registerLayer:(UMLayerSctp *)sctp forAssoc:(NSNumber *)assocId;

@end
