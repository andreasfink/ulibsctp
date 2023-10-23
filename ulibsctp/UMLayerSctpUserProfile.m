//
//  UMLayerSctpUserProfile.m
//  ulibsctp
//
//  Created by Andreas Fink on 03.12.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMLayerSctpUserProfile.h"

@implementation UMLayerSctpUserProfile


@synthesize allMessages;
@synthesize statusUpdates;
@synthesize streamIds;
@synthesize protocolIds;
@synthesize monitoring;

- (UMLayerSctpUserProfile *)initWithDefaultProfile
{
    self = [super init];
    if(self)
    {
        allMessages = YES;
        statusUpdates = YES;
        monitoring = NO;
    }
    return self;
}

- (BOOL) wantsStreamId:(NSNumber *)stream
{
    if(allMessages)
    {
        return YES;
    }
    if(streamIds ==NULL)
    {
        return YES;
    }
    for(NSNumber *n in streamIds)
    {
        if (n.unsignedLongValue == stream.unsignedLongValue)
        {
            return YES;
        }
    }
    return NO;
}

- (BOOL) wantsProtocolId:(NSNumber *)proto
{
    if(allMessages)
    {
        return YES;
    }
    if(protocolIds ==NULL)
    {
        return YES;
    }
    for(NSNumber *n in protocolIds)
    {
        if (n.unsignedLongValue == proto.unsignedLongValue)
        {
            return YES;
        }
    }
    return NO;
}


- (BOOL) wantsStatusUpdates
{
    if(statusUpdates)
    {
        return YES;
    }
    return NO;
}

- (BOOL) wantsMonitor
{
    if(monitoring)
    {
        return YES;
    }
    return NO;
}

@end

