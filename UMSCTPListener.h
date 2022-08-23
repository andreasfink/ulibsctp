//
//  UMSCTPListener.h
//  ulibsctp
//
//  Created by Andreas Fink on 23.08.22.
//  Copyright © 2022 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMSocketSCTP.h"

@class UMLayerSctp;
@class UMSocketSCTPReceivedPacket;

@protocol UMSCTPListenerProcessEventsDelegate

- (void) processError:(UMSocketError)err socket:(UMSocketSCTP *)s inArea:(NSString *)str layer:(id)layer;
- (void) processHangupOnSocket:(UMSocketSCTP *)s inArea:(NSString *)str layer:(id)layer;
- (void) processInvalidValueOnSocket:(UMSocketSCTP *)s inArea:(NSString *)str layer:(id)layer;

@end

@protocol UMSCTPListenerProcessDataDelegate
- (void) processReceivedData:(UMSocketSCTPReceivedPacket *)rx;
@end

@protocol UMSCTPListenerReadPacketDelegate
- (UMSocketSCTPReceivedPacket *)receiveSCTP;
@end


@interface UMSCTPListener : UMBackgrounder
{
    UMLayerSctp                                 *_layer;
    UMSocketSCTP                                *_umsocket;
    id<UMSCTPListenerProcessEventsDelegate>     _eventDelegate;
    id<UMSCTPListenerProcessDataDelegate>       _dataDelegate;
    id<UMSCTPListenerReadPacketDelegate>        _readDelegate;
    int                                         _timeoutInMs;
    
}

@property(readwrite,strong,atomic)  UMLayer                                    *layer;
@property(readwrite,strong,atomic)  UMSocketSCTP                               *umsocket;
@property(readwrite,strong,atomic)  id<UMSCTPListenerProcessEventsDelegate>    eventDelegate;
@property(readwrite,strong,atomic)  id<UMSCTPListenerProcessDataDelegate>      dataDelegate;
@property(readwrite,strong,atomic)  id<UMSCTPListenerReadPacketDelegate>       readDelegate;

@end

