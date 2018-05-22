//
//  UMLayerSctp.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMLayerSctpStatus.h"
#import "UMLayerSctpUserProtocol.h"
#import "UMLayerSctpApplicationContextProtocol.h"
#import "UMSocketSCTP.h"

@class UMSctpTask_AdminInit;
@class UMSctpTask_AdminSetConfig;
@class UMSctpTask_AdminAttach;
@class UMSctpTask_AdminDetach;
@class UMSctpTask_Open;
@class UMSctpTask_Close;
@class UMSctpTask_Data;
@class UMSctpTask_Manual_InService;
@class UMSctpTask_Manual_ForceOutOfService;
@class UMLayerSctpUser;
@class UMLayerSctpUserProfile;
@class UMSocketSCTPRegistry;
@class UMSocketSCTPListener;

@interface UMLayerSctp : UMLayer
{
    UMSocketSCTP    *_sctpSocket;
    UMSynchronizedArray *_users;
    
    SCTP_Status     _status;
    UMBackgrounder  *receiverThread;
    NSArray         *configured_local_addresses;
    int             configured_local_port;
    NSArray         *configured_remote_addresses;
    int             configured_remote_port;
    NSArray         *active_local_addresses;
    int             active_local_port;
    NSArray         *active_remote_addresses;
    int             active_remote_port;
    BOOL            isPassive;
    int             timeoutInMs; /* poll timeout in receiver thread . Default 400ms */
    NSTimeInterval  _heartbeatSeconds;
    UMThroughputCounter *_inboundThroughputPackets;
    UMThroughputCounter *_outboundThroughputPackets;
    UMThroughputCounter *_inboundThroughputBytes;
    UMThroughputCounter *_outboundThroughputBytes;
    /* these properties can be used by a gui to keep track of valid actions */
    NSDate          *_startButtonPressed;
    NSDate          *_stopButtonPressed;
    UMSocketSCTPRegistry *_registry;
    UMSocketSCTPListener *_listener;
    BOOL    _listenerStarted;
    UMTimer          *_reconnectTimer;
    NSTimeInterval  _reconnectTimerValue;
}

@property(readwrite,strong) UMSocketSCTP    *sctpSocket;

@property(readwrite,strong) NSDate          *startButtonPressed;
@property(readwrite,strong) NSDate          *stopButtonPressed;

@property(readwrite,assign,atomic) SCTP_Status     status;
@property(readwrite,strong) UMBackgrounder  *receiverThread;

@property(readwrite,strong  )NSArray    *configured_local_addresses;
@property(readwrite,assign) int         configured_local_port;
@property(readwrite,strong) NSArray     *configured_remote_addresses;
@property(readwrite,assign) int         configured_remote_port;

@property(readwrite,strong) NSArray         *active_local_addresses;
@property(readwrite,assign) int             active_local_port;
@property(readwrite,strong) NSArray         *active_remote_addresses;
@property(readwrite,assign) int             active_remote_port;

@property(readwrite,assign) BOOL            isPassive;
@property(readwrite,strong) UMLayerSctpUser *defaultUser;
@property(readwrite,assign) NSTimeInterval  heartbeatSeconds;

@property(readwrite,strong,atomic)      UMThroughputCounter *inboundThroughputPackets;
@property(readwrite,strong,atomic)      UMThroughputCounter *inboundThroughputBytes;
@property(readwrite,strong,atomic)      UMThroughputCounter *outboundThroughputPackets;
@property(readwrite,strong,atomic)      UMThroughputCounter *outboundThroughputBytes;
@property(readwrite,strong) UMSocketSCTPRegistry *registry;
@property(readwrite,strong) UMSocketSCTPListener *listener;

- (UMLayerSctp *)initWithTaskQueueMulti:(UMTaskQueueMulti *)tq;
- (UMLayerSctp *)initWithTaskQueueMulti:(UMTaskQueueMulti *)tq name:(NSString *)name;

/* LAYER API. The following methods queue a task */
#pragma mark -
#pragma mark Task Creators

- (void)adminInit;
- (void)adminSetConfig:(NSDictionary *)config applicationContext:(id<UMLayerSctpApplicationContextProtocol>)appContext;
- (void)adminAttachFor:(id<UMLayerSctpUserProtocol>)caller
               profile:(UMLayerSctpUserProfile *)p
                userId:(id)uid;
- (void)adminDetachFor:(id<UMLayerSctpUserProtocol>)caller
                userId:(id)uid;

- (void)openFor:(id<UMLayerSctpUserProtocol>)caller;
- (void)closeFor:(id<UMLayerSctpUserProtocol>)caller;
- (void)dataFor:(id<UMLayerSctpUserProtocol>)caller
           data:(NSData *)sendingData
       streamId:(uint16_t)sid
     protocolId:(uint32_t)pid
     ackRequest:(NSDictionary *)ack;
- (void)foosFor:(id<UMLayerSctpUserProtocol>)caller;
- (void)isFor:(id<UMLayerSctpUserProtocol>)caller;

/* LAYER API. The following methods are called by queued tasks */
#pragma mark -
#pragma mark Task Executors

- (void)_adminInitTask:(UMSctpTask_AdminInit *)task;
- (void)_adminSetConfigTask:(UMSctpTask_AdminSetConfig *)task;
- (void)_adminAttachTask:(UMSctpTask_AdminAttach *)task;
- (void)_adminDetachTask:(UMSctpTask_AdminDetach *)task;
- (void)_openTask:(UMSctpTask_Open *)task;
- (void)_closeTask:(UMSctpTask_Close *)task;
- (void)_dataTask:(UMSctpTask_Data *)task;
- (void)_foosTask:(UMSctpTask_Manual_ForceOutOfService *)task;
- (void)_isTask:(UMSctpTask_Manual_InService *)task;

/* internal direct calls */
#pragma mark -
#pragma mark Helpers

- (void)powerdown;
- (void) powerdownInReceiverThread;
- (void)reportStatus;
- (void)setNonBlocking;
- (void)setBlocking;
- (void)receiveData;
- (UMSocketError) dataIsAvailableSCTP:(int *)hasData
                               hangup:(int *)hasHup;

#pragma mark -
#pragma mark Config Handling
- (void)setConfig:(NSDictionary *)cfg applicationContext:(id<UMLayerSctpApplicationContextProtocol>)appContext;
- (NSDictionary *)config;
- (NSDictionary *)apiStatus;
- (void)stopDetachAndDestroy;
- (NSString *)statusString;

-(void) handleEvent:(NSData *)event
           streamId:(uint32_t)streamId
         protocolId:(uint16_t)protocolId;
- (void)processReceivedData:(UMSocketSCTPReceivedPacket *)rx;
- (void)processHangUp;
- (void)processInvalidSocket;

@end
