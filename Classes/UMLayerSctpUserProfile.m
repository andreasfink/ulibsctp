//
//  UMLayerSctpUserProfile.m
//  ulibsctp
//
//  Created by Andreas Fink on 03.12.14.
//  Copyright (c) 2016 Andreas Fink
//

#import "UMLayerSctpUserProfile.h"

@implementation UMLayerSctpUserProfile


@synthesize allMessages;
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

- (BOOL) wantsStreamId:(int)stream
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
        if (n.intValue == stream)
        {
            return YES;
        }
    }
    return NO;
}

- (BOOL) wantsProtocolId:(int)proto
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
        if (n.intValue == proto)
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

