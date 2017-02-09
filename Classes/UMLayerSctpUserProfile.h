//
//  UMLayerSctpUserProfile.h
//  ulibsctp
//
//  Created by Andreas Fink on 03.12.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
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
@property(readwrite,assign) BOOL statusUpdates;
@property(readwrite,strong) NSArray *streamIds;
@property(readwrite,strong) NSArray *protocolIds;
@property(readwrite,assign) BOOL monitoring;

- (UMLayerSctpUserProfile *)initWithDefaultProfile;
- (BOOL) wantsStreamId:(int)stream;
- (BOOL) wantsProtocolId:(int)proto;
- (BOOL) wantsStatusUpdates;
- (BOOL) wantsMonitor;

@end
