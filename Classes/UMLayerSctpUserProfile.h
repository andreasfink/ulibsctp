//
//  UMLayerSctpUserProfile.h
//  ulibsctp
//
//  Created by Andreas Fink on 03.12.14.
//  Copyright (c) 2016 Andreas Fink
//

#import <ulib/ulib.h>

@interface UMLayerSctpUserProfile : UMObject
{
    BOOL allMessages;
    BOOL statusUpdates;
    NSArray *streamIds;
    NSArray *protocolIds;
    BOOL monitoring;
}

@property(readwrite,assign) BOOL allMessages;
@property(readwrite,strong) NSArray *streamIds;
@property(readwrite,strong) NSArray *protocolIds;
@property(readwrite,assign) BOOL monitoring;

- (UMLayerSctpUserProfile *)initWithDefaultProfile;
- (BOOL) wantsStreamId:(int)stream;
- (BOOL) wantsProtocolId:(int)proto;
- (BOOL) wantsStatusUpdates;
- (BOOL) wantsMonitor;

@end
