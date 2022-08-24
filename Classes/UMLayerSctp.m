//
//  UMLayerSctp.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#define ULIBSCTP_INTERNAL 1
//#define POWER_DEBUG         1
#include "ulibsctp_config.h"

#include <netinet/in.h>
#ifdef HAVE_SCTP_SCTP_H
#import <sctp/sctp.h>
#endif

#ifdef HAVE_NETINET_SCTP_H
#include <netinet/sctp.h>
#endif

#import "UMLayerSctp.h"

#import "UMSctpTask_AdminInit.h"
#import "UMSctpTask_AdminAttach.h"
#import "UMSctpTask_AdminDetach.h"
#import "UMSctpTask_AdminSetConfig.h"
#import "UMSctpTask_Open.h"
#import "UMSctpTask_Close.h"
#import "UMSctpTask_Data.h"
#import "UMSctpTask_Manual_InService.h"
#import "UMSctpTask_Manual_ForceOutOfService.h"
#import "UMLayerSctpUser.h"
#import "UMLayerSctpUserProfile.h"
#import "UMLayerSctpApplicationContextProtocol.h"
#import "UMSocketSCTPListener.h"
#import "UMSocketSCTPRegistry.h"
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netdb.h>
#import "UMSocketSCTP.h"
#include <arpa/inet.h>

#import "UMLayerSctpUser.h"
#import "UMSctpOverTcp.h"


@implementation UMLayerSctp

-(NSString *)layerType
{
    return @"sctp";
}

- (UMLayerSctp *)init
{
    self = [self initWithTaskQueueMulti:NULL name:@"sctp-dummy"];
    if(self)
    {
        _newDestination = YES;
        [self addToLayerHistoryLog:@"init"];
    }
    return self;
}

- (UMLayerSctp *)initWithTaskQueueMulti:(UMTaskQueueMulti *)tq name:(NSString *)name
{
    NSString *s = [NSString stringWithFormat:@"sctp/%@",name];
    self = [super initWithTaskQueueMulti:tq name:s];
    if(self)
    {
        _timeoutInMs = 2400;
        _heartbeatSeconds = 30.0;
        _users = [[UMSynchronizedArray alloc]init];
        _status = UMSOCKET_STATUS_OFF;
        _newDestination = YES;
        _inboundThroughputPackets   = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _inboundThroughputBytes     = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _outboundThroughputPackets  = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _outboundThroughputBytes    = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _reconnectTimerValue = 6.0;
        _reconnectTimer = [[UMTimer alloc]initWithTarget:self selector:@selector(reconnectTimerFires) object:NULL seconds:_reconnectTimerValue name:@"reconnect-timer" repeats:NO runInForeground:YES];
        NSString *lockName = [NSString stringWithFormat:@"sctp-layer-link-lock(%@)",name];
        _linkLock = [[UMMutex alloc]initWithName:lockName];
        [self addToLayerHistoryLog:@"initWithTaskQueueMulti"];
    }
    return self;
}

#pragma mark -
#pragma mark Task Creators
- (void)adminInit
{
    UMLayerTask *task = [[UMSctpTask_AdminInit alloc]initWithReceiver:self sender:NULL];
    [self queueFromAdmin:task];
}


- (void)adminAttachFor:(id<UMLayerSctpUserProtocol>)caller
               profile:(UMLayerSctpUserProfile *)p
                userId:(id)uid;

{
    UMLayerTask *task =  [[UMSctpTask_AdminAttach alloc]initWithReceiver:self
                                                                  sender:caller
                                                                 profile:p
                                                                  userId:uid];
    [self queueFromAdmin:task];
}

- (void)adminDetachFor:(id<UMLayerSctpUserProtocol>)caller
                userId:(id)uid
{
    UMLayerTask *task =  [[UMSctpTask_AdminDetach alloc]initWithReceiver:self
                                                                  sender:caller
                                                                  userId:uid];
    [self queueFromAdmin:task];
}

- (void)adminSetConfig:(NSDictionary *)cfg applicationContext:(id<UMLayerSctpApplicationContextProtocol>)appContext;
{
    UMLayerTask *task = [[UMSctpTask_AdminSetConfig alloc]initWithReceiver:self config:cfg applicationContext:appContext];
    [self queueFromAdmin:task];
}

- (void)openFor:(id<UMLayerSctpUserProtocol>)caller
{
    [self addToLayerHistoryLog:[NSString stringWithFormat:@"openFor(%@)",caller.layerName]];
    [self openFor:caller sendAbortFirst:NO];
}

- (void)openFor:(id<UMLayerSctpUserProtocol>)caller sendAbortFirst:(BOOL)abortFirst
{
    [self openFor:caller sendAbortFirst:abortFirst reason:NULL];
}

- (void)openFor:(id<UMLayerSctpUserProtocol>)caller sendAbortFirst:(BOOL)abortFirst reason:(NSString *)reason
{
    UMSctpTask_Open *task = [[UMSctpTask_Open alloc]initWithReceiver:self sender:caller];
    task.sendAbortFirst = abortFirst;
    task.reason = reason;
    [self addToLayerHistoryLog:[NSString stringWithFormat:@"openFor(%@) sendAbortFirst=YES reason=%@",caller.layerName, (reason ? reason : @"unspecified")]];
    [self queueFromUpper:task];
}

- (void)closeFor:(id<UMLayerSctpUserProtocol>)caller
{
    [self closeFor:caller reason:NULL];
}

- (void)closeFor:(id<UMLayerSctpUserProtocol>)caller reason:(NSString *)reason
{
    [self addToLayerHistoryLog:[NSString stringWithFormat:@"closeFor(%@) reason=%@",caller.layerName,reason? reason: @"unspecified"]];
    UMSctpTask_Close *task = [[UMSctpTask_Close alloc]initWithReceiver:self sender:caller];
    task.reason = reason;

    [self queueFromUpper:task];
   
}

/* public API for upper interface */

- (void)dataFor:(id<UMLayerSctpUserProtocol>)caller
           data:(NSData *)sendingData
       streamId:(uint16_t)sid
     protocolId:(uint32_t)pid
     ackRequest:(NSDictionary *)ack
{
    [self dataFor:caller
             data:sendingData
         streamId:sid
       protocolId:pid
       ackRequest:ack
      synchronous:YES];
}

/* public API for upper interface */
- (void)dataFor:(id<UMLayerSctpUserProtocol>)caller
           data:(NSData *)sendingData
       streamId:(uint16_t)sid
     protocolId:(uint32_t)pid
     ackRequest:(NSDictionary *)ack
    synchronous:(BOOL)sync
{
    @autoreleasepool
    {
        UMSctpTask_Data *task =
        [[UMSctpTask_Data alloc]initWithReceiver:self
                                          sender:caller
                                            data:sendingData
                                        streamId:@(sid)
                                      protocolId:@(pid)
                                      ackRequest:ack];
        if(sync)
        {
            [task main];
        }
        else
        {
            [self queueFromUpper:task];
        }
    }
}

- (void)foosFor:(id<UMLayerSctpUserProtocol>)caller
{
    [self addToLayerHistoryLog:[NSString stringWithFormat:@"foosFor(%@)",caller.layerName]];
    @autoreleasepool
    {
        UMSctpTask_Manual_ForceOutOfService *task =
        [[UMSctpTask_Manual_ForceOutOfService alloc]initWithReceiver:self sender:caller];
        [self queueFromLowerWithPriority:task];
    }
}

- (void)isFor:(id<UMLayerSctpUserProtocol>)caller
{
    [self addToLayerHistoryLog:[NSString stringWithFormat:@"isFor(%@)",caller.layerName]];
    @autoreleasepool
    {
        UMSctpTask_Manual_InService *task =
        [[UMSctpTask_Manual_InService alloc]initWithReceiver:self sender:caller];
        [self queueFromLowerWithPriority:task];
    }
}

#pragma mark -
#pragma mark Task Executors
/* LAYER API. The following methods are called by queued tasks */
- (void)_adminInitTask:(UMSctpTask_AdminInit *)task
{
    @autoreleasepool
    {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"adminInit"]];
        }
    #endif
    }
}

- (void)_adminSetConfigTask:(UMSctpTask_AdminSetConfig *)task
{
    @autoreleasepool
    {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"setConfig %@",task.config]];
        }
    #endif
        [self setConfig:task.config applicationContext:task.appContext];
    }
}

- (void)_adminAttachTask:(UMSctpTask_AdminAttach *)task
{
    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

    UMLayerSctpUser *u      = [[UMLayerSctpUser alloc]init];
    u.profile              = task.profile;
    u.user                  = user;
    u.userId                = task.userId;

    [_users addObject:u];
    if(_defaultUser==NULL)
    {
        _defaultUser = u;
    }

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"attached %@",
                        user.layerName]];
    }
#endif
    [user adminAttachConfirm:self
                      userId:u.userId];
}

- (void)_adminDetachTask:(UMSctpTask_AdminDetach *)task
{
    NSArray *usrs = [_users arrayCopy];
    for(UMLayerSctpUser *u in usrs)
    {
        if([u.userId isEqualTo:task.userId])
        {
            [_users removeObject:u];
            [u.user adminDetachConfirm:self
                                userId:u.userId];
            break;
        }
    }
}

- (void)_openTask:(UMSctpTask_Open *)task
{
    @autoreleasepool
    {
        [self addToLayerHistoryLog:@"_openTask"];

        BOOL sendAbort = task.sendAbortFirst;
        [_linkLock lock];
        @try
        {
            if(self.status == UMSOCKET_STATUS_FOOS)
            {
                if(_logLevel <=UMLOG_DEBUG)
                {
                    NSLog(@"UMSOCKET_STATUS_FOOS");
                }
                [self logMajorError:@"OpenTask: failed due to M-FOOS"];
                [self addToLayerHistoryLog:@"OpenTask: failed due to M-FOOS"];

            }
            else if(self.status == UMSOCKET_STATUS_OOS)
            {
                [self logMinorError:@"already establishing"];
                [self addToLayerHistoryLog:@"OpenTask: already establishing"];

            }
            else if(self.status== UMSOCKET_STATUS_IS)
            {
                [self logMinorError:@"already in service"];
                [self addToLayerHistoryLog:@"OpenTask: already in service"];
                return;
            }
            else
            {
                UMSocketError err = UMSocketError_no_error;
                if(self.logLevel <= UMLOG_DEBUG)
                {
                    NSString *addrs = [_configured_local_addresses componentsJoinedByString:@","];
                    [self logDebug:[NSString stringWithFormat:@"getting listener on %@ on port %d",addrs,_configured_local_port]];
                }
                _listener =  [_registry getOrAddListenerForPort:_configured_local_port localIps:_configured_local_addresses];
                _listener.mtu = _mtu;
                _listener.dscp = _dscp;
                if(_minReceiveBufferSize > _listener.minReceiveBufferSize)
                {
                    _listener.minReceiveBufferSize = _minReceiveBufferSize;
                }
                if(_minSendBufferSize > _listener.minSendBufferSize)
                {
                    _listener.minSendBufferSize = _minSendBufferSize;
                }
                if(self.logLevel <= UMLOG_DEBUG)
                {
                    [self logDebug:[NSString stringWithFormat:@"asking listener %@ to start",_listener]];
                }
                
                else
                {
                    [_listener startListeningFor:self];
                    _listenerStarted = _listener.isListening;
                }
                _newDestination = YES;
                usleep(100000);
                _assocId = NULL;
                
                if(!_isPassive)
                {
                    if(self.logLevel <= UMLOG_DEBUG)
                    {
                        NSString *addrs = [_configured_remote_addresses componentsJoinedByString:@","];
                        NSString *s = [NSString stringWithFormat:@"asking listener to connect to %@ on port %d",addrs,_configured_remote_port];
                        [self logDebug:s];
                        [_layerHistory addLogEntry:s];
                    }

                    if(_directSocket)
                    {
                        if(sendAbort)
                        {
                            for(NSString *addr in _configured_remote_addresses)
                            {
                                @try
                                {
                                    [_listener.umsocket abortToAddress:addr
                                                                  port:_configured_remote_port
                                                                 assoc:_assocId
                                                                stream:0
                                                              protocol:0];
                                }
                                @catch(NSException *e)
                                {
                                }
                            }
                        }
                        [_directSocket close];
                        [self setStatus:UMSOCKET_STATUS_OFF reason:@"closing old direct socket in openTask"];
                    }
                    NSNumber *tmp_assocId = NULL;
                    err = [_listener connectToAddresses:_configured_remote_addresses
                                                   port:_configured_remote_port
                                               assocPtr:&tmp_assocId
                                                  layer:self];
                    if((err == UMSocketError_no_error) || (err==UMSocketError_in_progress))
                    {
                        if(tmp_assocId !=NULL)
                        {
                            _assocId = tmp_assocId;
                        }
                        [self setStatus:UMSOCKET_STATUS_OOS reason:@"_listener connectToAddress was successfully executed"];
                    }
                    if(self.logLevel <= UMLOG_DEBUG)
                    {
                        NSString *e = [UMSocket getSocketErrorString:err];
                        [self logDebug:[NSString stringWithFormat:@"returns %d %@",err,e]];
                    }
                }
                [_registry registerOutgoingLayer:self allowAnyRemotePortIncoming:_allowAnyRemotePortIncoming];
                if(_allowAnyRemotePortIncoming)
                {
                    [_registry registerIncomingLayer:self];
                }
                if(_assocId!=NULL)
                {
                    [_registry registerAssoc:_assocId forLayer:self];
                }
                [_registry startReceiver];
            }
        }
        @catch (NSException *exception)
        {
            [_layerHistory addLogEntry:[NSString stringWithFormat:@"Exception: %@",exception]];
            NSNumber *e = exception.userInfo[@"errno"];
            int err = e.intValue;
            if(self.logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"%@ %@",exception.name,exception.reason]];
            }
            if(exception.userInfo)
            {
                if(e)
                {
                    [self logMajorError:[NSString stringWithFormat:@"%@ %@",exception.name,exception.reason]];
                }
            }
            if((err != EINPROGRESS) && (err != EAGAIN))
            {
                [self powerdown:[NSString stringWithFormat:@"errno=%d exception:%@ %@",err,exception.name,exception.reason] ];
            }
        }
        [_linkLock unlock];
    }
 }

- (void)_closeTask:(UMSctpTask_Close *)task
{
    @autoreleasepool
    {
        [self addToLayerHistoryLog:@"_closeTask"];
        [_linkLock lock];
        @try
        {
#if defined(ULIBSCTP_CONFIG_DEBUG)
            if(self.logLevel <=UMLOG_DEBUG)
            {
                id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;
                [self logDebug:[NSString stringWithFormat:@"closing for %@",user.layerName]];
            }
#endif
            [self powerdown:@"_closeTask"];
            if(_listenerStarted==YES)
            {
                [_listener stopListeningFor:self];
            }
            _listener = NULL;
        }
        @catch(NSException *e)
        {
            if(_logLevel <=UMLOG_DEBUG)
            {
                NSLog(@"%@",e);
            }
        }
        [_linkLock unlock];
#if defined(POWER_DEBUG)
        NSLog(@"%@ closeTask(end)",_layerName);
#endif
        [self reportStatus];
    }
}


- (void)reportError:(UMSocketError)err taskData:(UMSctpTask_Data *)task
{

    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

    NSString *errString= [UMSocket getSocketErrorString:err];;
    [self addToLayerHistoryLog:[NSString stringWithFormat:@"reportError(%d) %@",err,errString]];
    [self logMajorError:[NSString stringWithFormat:@"%@",errString]];
    if(task.ackRequest)
    {
        NSMutableDictionary *report = [task.ackRequest mutableCopy];
        NSDictionary *ui = @{
                         @"protocolId" : task.protocolId,
                         @"streamId"   : task.streamId,
                         @"data"       : task.data
                         };
        [report setObject:ui forKey:@"sctp_data"];
        NSDictionary *errDict = @{
                              @"exception"  : errString,
                              };
        [report setObject:errDict forKey:@"sctp_error"];
        [user sentAckFailureFrom:self
                    userInfo:report
                       error:errString
                      reason:@""
                   errorInfo:errDict];
    }
}

- (void)_dataTask:(UMSctpTask_Data *)task
{
    BOOL linkLocked=NO;
    UMSleeper *sleeper = [[UMSleeper alloc]initFromFile:__FILE__ line:__LINE__ function:__func__];
    @autoreleasepool
    {
        id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"DATA: %@",task.data]];
            [self logDebug:[NSString stringWithFormat:@" streamId: %@",task.streamId]];
            [self logDebug:[NSString stringWithFormat:@" protocolId: %@",task.protocolId]];
            [self logDebug:[NSString stringWithFormat:@" ackRequest: %@",(task.ackRequest ? task.ackRequest.description  : @"(not present)")]];
        }
    #endif
        
        if(task.data == NULL)
        {
            /* nothing to be done */
            return;
        }
        
        BOOL failed = NO;
        UMSocketError uerr = UMSocketError_no_error;

        ssize_t sent_packets = 0;
        int attempts=0;
        /* we try to send as long as no ASSOC down has been received or at least once (as we might not have a direct socket yet */
        int maxatt = 50;
        while((attempts < maxatt) && (self.status==UMSOCKET_STATUS_IS) && (sent_packets<1))
        {
            attempts++;
            [_linkLock lock];
            linkLocked = YES;
            if(_directSocket)
            {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <= UMLOG_DEBUG)
                {
                    [self logDebug:[NSString stringWithFormat:@" Calling sctp_sendmsg on _directsocket (%@)",[_configured_remote_addresses componentsJoinedByString:@","]]];
                }
    #endif
                NSNumber *tmp_assocId = _assocId;
                sent_packets = [_directSocket sendToAddresses:_configured_remote_addresses
                                                         port:_configured_remote_port
                                                     assocPtr:&tmp_assocId
                                                         data:task.data
                                                       stream:task.streamId
                                                     protocol:task.protocolId
                                                        error:&uerr];
                _assocId = tmp_assocId ;
            }
            else if(_directTcpEncapsulatedSocket)
            {
                [self sendEncapsulated:task.data
                                 assoc:_assocId
                                stream:task.streamId
                              protocol:task.protocolId
                                 error:&uerr
                                 flags:0];
            }
            else
            {
                NSNumber *tmp_assocId = _assocId;
                sent_packets = [_listener sendToAddresses:_configured_remote_addresses
                                                     port:_configured_remote_port
                                                 assocPtr:&tmp_assocId
                                                     data:task.data
                                                   stream:task.streamId
                                                 protocol:task.protocolId
                                                    error:&uerr
                                                    layer:self];
                _assocId = tmp_assocId;
            }
            [_linkLock unlock];
            linkLocked = NO;
            
            /*  we loop until we get errno not EAGAIN or sent_packets returning > 0 */
            if(sent_packets > 0)
            {
                break;
            }
            if(uerr != UMSocketError_try_again)
            {
                failed=YES;
                break;
            }
            if(uerr == UMSocketError_try_again)
            {
                /* we have EAGAIN */
                /* lets try up to 50 times and wait 200ms every 10th time */
                /* if thats still not succeeding, we declare this connection dead */
                if(attempts % 10==0)
                {
                    [sleeper sleepSeconds:0.2];
                }
                if(attempts < maxatt)
                {
                    continue;
                }
                
                /* if we get here we have attempted 50 times and failed */
                /* we can assume this connection dead */
                NSString *s = @"tried to send 50 times and got UMSocketError_try_again every time";
                [_layerHistory addLogEntry:s];
                failed=YES;
            }
        }
        
#if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@" sent_packets: %ld",sent_packets]];
        }
#endif
        if(sent_packets>0)
        {
            [_outboundThroughputPackets increaseBy:1];
            [_outboundThroughputBytes increaseBy:(uint32_t)task.data.length];
            NSArray *usrs = [_users arrayCopy];
            for(UMLayerSctpUser *u in usrs)
            {
                if([u.profile wantsMonitor])
                {
                    [u.user sctpMonitorIndication:self
                                           userId:u.userId
                                         streamId:(uint16_t)task.streamId.unsignedIntValue
                                       protocolId:(uint32_t)task.protocolId.unsignedLongValue
                                             data:task.data
                                         incoming:NO];
                }
            }
            NSDictionary *ui = @{
                                 @"protocolId" : task.protocolId,
                                 @"streamId"   : task.streamId,
                                 @"data"       : task.data
                                 };
            NSMutableDictionary *report = [task.ackRequest mutableCopy];
            [report setObject:ui forKey:@"sctp_data"];
            //report[@"backtrace"] = UMBacktrace(NULL,0);
            [user sentAckConfirmFrom:self userInfo:report];
        }
        else if(failed)
        {
            NSString *s = [NSString stringWithFormat:@"Error %d %@",uerr,[UMSocket getSocketErrorString:uerr]];
            [_layerHistory addLogEntry:s];

            if(uerr==UMSocketError_is_already_connected)
            {
                if(_logLevel <=UMLOG_MINOR)
                {
                    NSLog(@"already connected");
                }
            }
            [self reportError:uerr taskData:task];
            [self powerdown:@"error in _dataTask"];
            [self reportStatus];
        }
    }
}

- (void)_foosTask:(UMSctpTask_Manual_ForceOutOfService *)task
{
    @autoreleasepool
    {
        [self addToLayerHistoryLog:@"_foosTask" ];

        [_linkLock lock];
        [self powerdown:@"_foosTask"];
        [self setStatus:UMSOCKET_STATUS_FOOS reason:@"FOOS requested"];
    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <=UMLOG_DEBUG)
        {
            [self logDebug:@"FOOS"];
        }
    #endif
        [_linkLock unlock];
#if defined(POWER_DEBUG)
        NSLog(@"%@ manual FOOS",_layerName);
#endif
        [self reportStatus];
    }
}

- (void)_isTask:(UMSctpTask_Manual_InService *)task
{
    @autoreleasepool
    {
        [self addToLayerHistoryLog:@"_isTask" ];

        id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

        switch(self.status)
        {
            case UMSOCKET_STATUS_FOOS:
#if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <=UMLOG_DEBUG)
                {
                    [self logDebug:@"manual M-FOOS->IS requested"];
                }
#endif
#if defined(POWER_DEBUG)
                NSLog(@"%@ manual M-FOOS->IS requested",_layerName);
#endif
                [self setStatus:UMSOCKET_STATUS_OFF reason:@"_isTask"];

#if defined(POWER_DEBUG)
                NSLog(@"%@ isTask(OFF)",_layerName);
#endif
                [self reportStatus];
#if defined(POWER_DEBUG)
                NSLog(@"%@ call openFor",_layerName);
#endif

                [self openFor:user sendAbortFirst:NO];
                break;
            case UMSOCKET_STATUS_OFF:
    #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <=UMLOG_DEBUG)
                {
                    [self logDebug:@"manual OFF->IS requested"];
                }
    #endif
#if defined(POWER_DEBUG)
                NSLog(@"%@ manual OFF->IS requested",_layerName);
#endif
                [self openFor:user];
                break;
                
            case UMSOCKET_STATUS_OOS:
    #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <=UMLOG_DEBUG)
                {
                    [self logDebug:@"manual OOS->IS requested"];
                }
    #endif
                [self reportStatus];
                break;

            case UMSOCKET_STATUS_IS:
    #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <=UMLOG_DEBUG)
                {
                    [self logDebug:@"manual IS->IS requested"];
                }
    #endif
#if defined(POWER_DEBUG)
                NSLog(@"%@ manual IS->IS requested",_layerName);
#endif
                [self reportStatus];
                break; 
            case UMSOCKET_STATUS_LISTENING:
            #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <=UMLOG_DEBUG)
                {
                    [self logDebug:@"manual LISTENING->IS requested"];
                }
            #endif
#if defined(POWER_DEBUG)
                NSLog(@"%@ manual LISTENING->IS requested",_layerName);
#endif
                [self reportStatus];
                break;
        }
    }
}


#pragma mark -
#pragma mark Helpers

- (void)powerdown
{
    [self powerdown:NULL];
}

- (void) powerdown:(NSString *)reason
{
    @autoreleasepool
    {
        if(reason)
        {
            [self addToLayerHistoryLog:[NSString stringWithFormat:@"powerdown (reason=%@)",reason]];
        }
        else
        {
            [self addToLayerHistoryLog:@"powerdown"];
        }
   #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self.logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
        }
    #endif
        //[_receiverThread shutdownBackgroundTask];
        [self setStatus:UMSOCKET_STATUS_OOS reason:@"powerdown"];
        [self setStatus:UMSOCKET_STATUS_OFF reason:@"powerdown"];

        if(_assocId!=NULL)
        {
            [_registry unregisterAssoc:_assocId];
            _assocId = NULL;
            /*
            for(NSString *addr in _configured_remote_addresses)
            {
                [_listener.umsocket abortToAddress:addr
                                              port:(_active_remote_port>0 ? _active_remote_port :  _configured_remote_port)
                                             assoc:_assocId
                                            stream:0
                                          protocol:0];
            }
            */
            if(_directSocket)
            {
                [_directSocket close];
                [_registry unregisterAssoc:_assocId];
                _assocId=NULL;
                [_registry unregisterLayer:self];
            }
            if(_directTcpEncapsulatedSocket)
            {
                [_directTcpEncapsulatedSocket close];
                if(_isPassive)
                {
                    [_registry unregisterIncomingTcpLayer:self];
                }
            }
            _directSocket = NULL;
            _directTcpEncapsulatedSocket = NULL;
        }
    }
}

- (void) powerdownInReceiverThread
{
    [self powerdownInReceiverThread:NULL];
}

- (void) powerdownInReceiverThread:(NSString *)reason
{
    @autoreleasepool
    {
        [self addToLayerHistoryLog:[NSString stringWithFormat:@"powerdownInReceiverThread %@",reason ? reason : @""]];
    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self.logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
        }
    #endif
        [self setStatus:UMSOCKET_STATUS_OFF reason:@"powerdownInReceiverThread"];
        if(_assocId!=NULL)
        {
            [_registry unregisterAssoc:_assocId];
            _assocId = NULL;
        }
        [_directSocket close];
        [_registry unregisterAssoc:_assocId];
        _assocId=NULL;
        _directSocket = NULL;
    }
}

- (void)reportStatus
{
    @autoreleasepool
    {
        NSArray *usrs = [_users arrayCopy];
        for(UMLayerSctpUser *u in usrs)
        {
            if([u.profile wantsStatusUpdates])
            {
                [u.user sctpStatusIndication:self
                                      userId:u.userId
                                      status:self.status];
            }
        }
    }
}


- (void)processReceivedData:(UMSocketSCTPReceivedPacket *)rx
{
    @autoreleasepool
    {
        BOOL peeloffFailed = NO;
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSMutableString *s = [[NSMutableString alloc]init];
        [s appendFormat:@"processReceivedData: \n%@",rx.description];
        [self logDebug:s];
#endif
        if(!_encapsulatedOverTcp)
        {
            if(rx.assocId !=NULL)
            {
                _assocId = rx.assocId;
                if(_directSocket == NULL)
                {
#if defined(ULIBSCTP_CONFIG_DEBUG)
                    [self logDebug:[NSString stringWithFormat:@"processReceivedData: Peeling of assoc %@",rx.assocId]];
#endif
                    UMSocketError err = UMSocketError_no_error;
                    _directSocket = [_listener peelOffAssoc:rx.assocId error:&err];
                    [_layerHistory addLogEntry:[NSString stringWithFormat:@"processReceivedData: peeling off assoc %lu into socket %p/%d err=%d",(unsigned long)_assocId.unsignedLongValue,_directSocket,_directSocket.sock,err]];
                    if((err != UMSocketError_no_error) && (err !=UMSocketError_in_progress))
                    {
                        peeloffFailed = YES;
                    }
                }
            }
        }
        if(rx.err==UMSocketError_try_again)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            if(_logLevel <=UMLOG_DEBUG)
            {
                NSLog(@"receiveData: UMSocketError_try_again returned by receiveSCTP");
            }
    #endif
        }
        else if(rx.err==UMSocketError_invalid_file_descriptor)
        {
            if(_logLevel <=UMLOG_DEBUG)
            {
                NSLog(@"receiveData: UMSocketError_invalid_file_descriptor returned by receiveSCTP");
            }
            [self powerdownInReceiverThread:@"invalid_file_descriptor"];
            [self reportStatus];
        }
        else if(rx.err==UMSocketError_connection_reset)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            if(_logLevel <=UMLOG_DEBUG)
            {
                NSLog(@"receiveData: UMSocketError_connection_reset returned by receiveSCTP");
            }
    #endif
            [self logDebug:@"ECONNRESET"];
#if defined(POWER_DEBUG)
            NSLog(@"%@ powerdown due to ECONNRESET",_layerName);
#endif
            [self powerdownInReceiverThread:@"ECONNRESET"];
            [self reportStatus];
        }

        else if(rx.err==UMSocketError_connection_aborted)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            if(_logLevel <=UMLOG_DEBUG)
            {
                NSLog(@"receiveData: UMSocketError_connection_aborted returned by receiveSCTP");
            }
    #endif
            [self logDebug:@"ECONNABORTED"];
#if defined(POWER_DEBUG)
            NSLog(@"%@ powerdown due to ECONNABORTED",_layerName);
#endif
            [self powerdownInReceiverThread];
            [self reportStatus];
        }
        else if(rx.err==UMSocketError_connection_refused)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            if(_logLevel <=UMLOG_DEBUG)
            {
                NSLog(@"receiveData: UMSocketError_connection_refused returned by receiveSCTP");
            }
    #endif
            [self logDebug:@"ECONNREFUSED"];
            sleep(1);
#if defined(POWER_DEBUG)
            NSLog(@"%@ powerdown due to ECONNREFUSED",_layerName);
#endif
            [self powerdownInReceiverThread:@"ECONNREFUSED"];
            [self reportStatus];
        }
        else if(rx.err != UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"receiveData: Error %d %@ returned by receiveSCTP",rx.err,[UMSocket getSocketErrorString:rx.err]]];
#if defined(POWER_DEBUG)
            NSLog(@"%@ powerdown due to Error %d %@ returned by receiveSCTP",_layerName,rx.err,[UMSocket getSocketErrorString:rx.err]);
#endif
            [self powerdownInReceiverThread:[NSString stringWithFormat:@"rx.err=%@",[UMSocket getSocketErrorString:rx.err]]];
            [self reportStatus];
        }
        else if(peeloffFailed)
        {
            [_directSocket close];
            [_registry unregisterAssoc:_assocId];
            _assocId=NULL;
            _directSocket = NULL;
            NSString *s = [NSString stringWithFormat:@"processReceivedData peeloff failed"];
            [self logMinorError:s];
            [self powerdownInReceiverThread:s];
            [self reportStatus];
        }
        else
        {
            if(rx.flags & SCTP_OVER_TCP_SETUP_CONFIRM)
            {
                [self setStatus:UMSOCKET_STATUS_IS reason:@"SCTP_OVER_TCP_SETUP_CONFIRM"];

#if defined(POWER_DEBUG)
                NSLog(@"%@ SCTP_OVER_TCP_SETUP_CONFIRM",_layerName);
#endif
                [self reportStatus];
            }
            else if(rx.isNotification)
            {
                [self handleEvent:rx.data
                         streamId:rx.streamId
                       protocolId:rx.protocolId];
            }
            else
            {
                [self sctpReceivedData:rx.data
                              streamId:rx.streamId
                            protocolId:rx.protocolId];
            }
        }
    }
}

-(void) handleEvent:(NSData *)event
           streamId:(NSNumber *)streamId
         protocolId:(NSNumber *)protocolId
{
    @autoreleasepool
    {
        const union sctp_notification *snp;
        snp = event.bytes;
        switch(snp->sn_header.sn_type)
        {
            case SCTP_ASSOC_CHANGE:
                [self handleAssocChange:event streamId:streamId protocolId:protocolId];
                break;
            case SCTP_PEER_ADDR_CHANGE:
                [self handlePeerAddrChange:event streamId:streamId protocolId:protocolId];
                break;
            case SCTP_SEND_FAILED:
                [self handleSendFailed:event streamId:streamId protocolId:protocolId];
                break;
            case SCTP_REMOTE_ERROR:
                [self handleRemoteError:event streamId:streamId protocolId:protocolId];
                break;
            case SCTP_SHUTDOWN_EVENT:
                [self handleShutdownEvent:event streamId:streamId protocolId:protocolId];
                break;
            case SCTP_PARTIAL_DELIVERY_EVENT:
                [self handleAdaptionIndication:event streamId:streamId protocolId:protocolId];
                break;
            case SCTP_ADAPTATION_INDICATION:
                [self handleAdaptionIndication:event streamId:streamId protocolId:protocolId];
                break;
    #if defined SCTP_AUTHENTICATION_EVENT
            case SCTP_AUTHENTICATION_EVENT:
                [self handleAuthenticationEvent:event streamId:streamId protocolId:protocolId];
                break;
    #endif
            case SCTP_SENDER_DRY_EVENT:
                [self handleSenderDryEvent:event streamId:streamId protocolId:protocolId];
                break;

    #if defined SCTP_STREAM_RESET_EVENT
            case  SCTP_STREAM_RESET_EVENT:
                [self handleStreamResetEvent:event streamId:streamId protocolId:protocolId];
                break;
    #endif

            default:
                [self.logFeed majorErrorText:[NSString stringWithFormat:@"SCTP unknown event type: %hu", snp->sn_header.sn_type]];
                [self.logFeed majorErrorText:[NSString stringWithFormat:@" RX-STREAM: %lu",streamId.unsignedLongValue]];
                [self.logFeed majorErrorText:[NSString stringWithFormat:@" RX-PROTO: %lu", protocolId.unsignedLongValue]];
                [self.logFeed majorErrorText:[NSString stringWithFormat:@" RX-DATA: %@",event.description]];
        }
    }
}


-(void) handleAssocChange:(NSData *)event
                 streamId:(NSNumber *)streamId
               protocolId:(NSNumber *)protocolId
{
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_ASSOC_CHANGE"];
    }
#endif
    if(len < sizeof (struct sctp_assoc_change))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_ASSOC_CHANGE"];
    }
    
    NSString *state = @"(UNKNOWN)";
    switch(snp->sn_assoc_change.sac_state)
    {
        case SCTP_COMM_UP:
            state =@"SCTP_COMM_UP";
            break;
        case SCTP_COMM_LOST:
            state =@"SCTP_COMM_LOST";
            break;
        case SCTP_RESTART:
            state =@"SCTP_RESTART";
            break;
        case SCTP_SHUTDOWN_COMP:
            state =@"SCTP_SHUTDOWN_COMP";
            break;
        case SCTP_CANT_STR_ASSOC:
            state =@"SCTP_CANT_STR_ASSOC";
            break;
    }
    [self addToLayerHistoryLog:state];
    
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  sac_type: %d",             (int)snp->sn_assoc_change.sac_type]];
        [self logDebug:[NSString stringWithFormat:@"  sac_flags: %d",            (int)snp->sn_assoc_change.sac_flags]];
        [self logDebug:[NSString stringWithFormat:@"  sac_length: %d",           (int)snp->sn_assoc_change.sac_length]];
        [self logDebug:[NSString stringWithFormat:@"  sac_state: %d %@",            (int)snp->sn_assoc_change.sac_state, state]];
        [self logDebug:[NSString stringWithFormat:@"  sac_error: %d",            (int)snp->sn_assoc_change.sac_error]];
        [self logDebug:[NSString stringWithFormat:@"  sac_outbound_streams: %d", (int)snp->sn_assoc_change.sac_outbound_streams]];
        [self logDebug:[NSString stringWithFormat:@"  sac_inbound_streams: %d",  (int)snp->sn_assoc_change.sac_inbound_streams]];
        [self logDebug:[NSString stringWithFormat:@"  sac_assoc_id: %d",         (int)snp->sn_assoc_change.sac_assoc_id]];
    }
#endif
    if((snp->sn_assoc_change.sac_state==SCTP_COMM_UP) && (snp->sn_assoc_change.sac_error== 0))
    {
        _listener.firstMessage=YES;
        _assocId = @(snp->sn_assoc_change.sac_assoc_id);
        [self.logFeed infoText:[NSString stringWithFormat:@" SCTP_ASSOC_CHANGE: SCTP_COMM_UP->IS (assocID=%ld)",(long)_assocId]];
        [self setStatus:UMSOCKET_STATUS_IS reason:@"COM_UP"];

        if(_directSocket==NULL)
        {
            UMSocketError err = UMSocketError_no_error;
            _directSocket = [_listener peelOffAssoc:_assocId error:&err];
            [_layerHistory addLogEntry:[NSString stringWithFormat:@"peeling off assoc %lu into socket %p/%d err=%d",(unsigned long)_assocId.unsignedLongValue,_directSocket,_directSocket.sock,err]];

            if((err != UMSocketError_no_error) && (err !=UMSocketError_in_progress) && (err!=UMSocketError_not_a_socket))
            {
                _directSocket = NULL;
                [_registry unregisterAssoc:_assocId];
                _assocId=NULL;
            }
            [_registry registerIncomingLayer:self];
        }
        [_reconnectTimer stop];
#if defined(POWER_DEBUG)
        NSLog(@"%@ SCTP_COMM_UP",_layerName);
#endif
        [self reportStatus];
    }
    else if(snp->sn_assoc_change.sac_state==SCTP_COMM_LOST)
    {
        _assocId = @(snp->sn_assoc_change.sac_assoc_id);
        if(_directSocket)
        {
            _directSocket.isConnected=NO;
        }
        [self.logFeed infoText:[NSString stringWithFormat:@" SCTP_ASSOC_CHANGE: SCTP_COMM_LOST->OFF (assocID=%ld)",(long)_assocId]];
#if defined(POWER_DEBUG)
        NSLog(@"%@ SCTP_COMM_LOST",_layerName);
#endif
        [self powerdownInReceiverThread:@"SCTP_COMM_LOST"];
        [self reportStatus];
#if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",_reconnectTimer.seconds]];
        }
#endif
        [_reconnectTimer stop];
        [_reconnectTimer start];
    }
    else if(snp->sn_assoc_change.sac_state==SCTP_CANT_STR_ASSOC)
    {
        if(_directSocket)
        {
            _directSocket.isConnected=NO;
        }
        [self.logFeed infoText:@" SCTP_ASSOC_CHANGE: SCTP_CANT_STR_ASSOC"];
#if defined(POWER_DEBUG)
        NSLog(@"%@ SCTP_CANT_STR_ASSOC",_layerName);
#endif
        [self powerdownInReceiverThread:@"SCTP_CANT_STR_ASSOC"];
        [self reportStatus];
#if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",_reconnectTimer.seconds]];
        }
#endif
        [_reconnectTimer stop];
        [_reconnectTimer start];
    }
    else if(snp->sn_assoc_change.sac_error!=0)
    {
        if(_directSocket)
        {
            _directSocket.isConnected=NO;
        }
        [self.logFeed majorError:snp->sn_assoc_change.sac_error withText:@" SCTP_ASSOC_CHANGE: SCTP_COMM_ERROR(%d)->OFF"];
#if defined(POWER_DEBUG)
        NSLog(@"%@ SCTP_ASSOC_CHANGE: SCTP_COMM_ERROR(%d)",_layerName,snp->sn_assoc_change.sac_error );
#endif
        [self powerdownInReceiverThread:[NSString stringWithFormat:@"SCTP_COMM_ERROR(%d)",snp->sn_assoc_change.sac_error]];
        [self reportStatus];
#if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",_reconnectTimer.seconds]];
        }
#endif
        [_reconnectTimer stop];
        [_reconnectTimer start];
    }
}

-(void) handleLinkUpTcpEcnap
{
    [self.logFeed infoText:[NSString stringWithFormat:@" SCTP_TCP_ASSOC_CHANGE: SCTP_COMM_UP->IS"]];
    [self setStatus:UMSOCKET_STATUS_IS reason:@"handleLinkUpTcpEcnap"];
    [_reconnectTimer stop];
#if defined(POWER_DEBUG)
    NSLog(@"%@ handleLinkUpTcpEcnap",_layerName);
#endif
    [self reportStatus];

}

-(void) handleLinkDownTcpEcnap
{
    _listener.firstMessage=YES;
    [self.logFeed infoText:[NSString stringWithFormat:@" SCTP_TCP_ASSOC_CHANGE: SCTP_COMM_LOST->OFF"]];
    [self setStatus:UMSOCKET_STATUS_OFF reason:@"handleLinkDownTcpEcnap"];
#if defined(POWER_DEBUG)
    NSLog(@"%@ handleLinkDownTcpEcnap",_layerName);
#endif

    [self powerdownInReceiverThread:@"handleLinkDownTcpEcnap"];
    [self reportStatus];
    [_reconnectTimer start];
}

-(void) handlePeerAddrChange:(NSData *)event
                    streamId:(NSNumber *)streamId
                  protocolId:(NSNumber *)protocolId
{
    const union sctp_notification *snp;

    char addrbuf[INET6_ADDRSTRLEN];
    const char *ap;
    struct sockaddr_in *sin;
    struct sockaddr_in6 *sin6;

    snp = event.bytes;
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_PEER_ADDR_CHANGE"];
    }
#endif
    if(len < sizeof (struct sctp_paddr_change))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_PEER_ADDR_CHANGE"];
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  spc_type: %d",    (int)snp->sn_paddr_change.spc_type]];
        [self logDebug:[NSString stringWithFormat:@"  spc_flags: %d",   (int)snp->sn_paddr_change.spc_flags]];
        [self logDebug:[NSString stringWithFormat:@"  spc_length: %d",  (int)snp->sn_paddr_change.spc_length]];
    }
#endif
    if (snp->sn_paddr_change.spc_aaddr.ss_family == AF_INET)
    {
        //struct sockaddr_in *sin;
        sin = (struct sockaddr_in *)&snp->sn_paddr_change.spc_aaddr;
        ap = inet_ntop(AF_INET, &sin->sin_addr, addrbuf, INET6_ADDRSTRLEN);
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"  spc_aaddr: ipv4:%s", ap]];
        }
    }
    else
    {
        sin6 = (struct sockaddr_in6 *)&snp->sn_paddr_change.spc_aaddr;
        ap = inet_ntop(AF_INET6, &sin6->sin6_addr, addrbuf, INET6_ADDRSTRLEN);
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"  spc_aaddr: ipv6:%s", ap]];
        }
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  spc_state: %d",   (int)snp->sn_paddr_change.spc_state]];
        [self logDebug:[NSString stringWithFormat:@"  spc_error: %d",   (int)snp->sn_paddr_change.spc_error]];
        if (snp->sn_paddr_change.spc_aaddr.ss_family == AF_INET)
        {
            [self logDebug:[NSString stringWithFormat:@" SCTP_PEER_ADDR_CHANGE: ipv4:%s",ap]];
        }
        else
        {
            [self logDebug:[NSString stringWithFormat:@" SCTP_PEER_ADDR_CHANGE: ipv6:%s",ap]];
        }
    }
#endif
}

-(void) handleRemoteError:(NSData *)event
                 streamId:(NSNumber *)streamId
               protocolId:(NSNumber *)protocolId
{
#if defined(ULIBSCTP_CONFIG_DEBUG)
    const union sctp_notification *snp;
    snp = event.bytes;
#endif
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_REMOTE_ERROR"];
    }
#endif
    if(len < sizeof (struct sctp_remote_error))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_REMOTE_ERROR"];
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)

    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  sre_type: %d",             (int)snp->sn_remote_error.sre_type]];
        [self logDebug:[NSString stringWithFormat:@"  sre_flags: %d",            (int)snp->sn_remote_error.sre_flags]];
        [self logDebug:[NSString stringWithFormat:@"  sre_length: %d",           (int)snp->sn_remote_error.sre_length]];
        [self logDebug:[NSString stringWithFormat:@"  sre_length: %d",           (int)snp->sn_remote_error.sre_error]];
        [self logDebug:[NSString stringWithFormat:@"  sre_assoc_id: %d",         (int)snp->sn_remote_error.sre_assoc_id]];
        [self logDebug:[NSString stringWithFormat:@"  sre_data: %02X %02X %02X %02x",
                        (int)snp->sn_remote_error.sre_data[0],
                        (int)snp->sn_remote_error.sre_data[1],
                        (int)snp->sn_remote_error.sre_data[2],
                        (int)snp->sn_remote_error.sre_data[3]]];
    }
#endif
}


-(int) handleSendFailed:(NSData *)event
               streamId:(NSNumber *)streamId
             protocolId:(NSNumber *)protocolId
{
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;


#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_SEND_FAILED"];
    }
#endif
    if(len < sizeof (struct sctp_send_failed))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_SEND_FAILED"];
#if defined(POWER_DEBUG)
        NSLog(@"%@ SCTP_SEND_FAILED(size mismatch)",_layerName);
#endif
        [self powerdownInReceiverThread:@"Size Mismatch in SCTP_SEND_FAILED"];
        [self reportStatus];
        return UMSocketError_not_supported_operation;
    }
    [self.logFeed majorErrorText:@"SCTP_SEND_FAILED"];
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  ssf_type: %d",                (int)snp->sn_send_failed.ssf_type]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_flags: %d",               (int)snp->sn_send_failed.ssf_flags]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_length: %d",              (int)snp->sn_send_failed.ssf_length]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_error: %d",               (int)snp->sn_send_failed.ssf_error]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_assoc_id: %d",            (int)snp->sn_send_failed.ssf_assoc_id]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_stream: %d",   (int)snp->sn_send_failed.ssf_info.sinfo_stream]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_ssn: %d",      (int)snp->sn_send_failed.ssf_info.sinfo_ssn]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_flags: %d",    (int)snp->sn_send_failed.ssf_info.sinfo_flags]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_stream: %d",   (int)snp->sn_send_failed.ssf_info.sinfo_stream]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_context: %d",  (int)snp->sn_send_failed.ssf_info.sinfo_context]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_timetolive: %d",(int)snp->sn_send_failed.ssf_info.sinfo_timetolive]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_tsn: %d",      (int)snp->sn_send_failed.ssf_info.sinfo_tsn]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_cumtsn: %d",   (int)snp->sn_send_failed.ssf_info.sinfo_cumtsn]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_info.sinfo_assoc_id: %d", (int)snp->sn_send_failed.ssf_info.sinfo_assoc_id]];
        [self logDebug:[NSString stringWithFormat:@"  ssf_assoc_id: %d",    (int)snp->sn_send_failed.ssf_assoc_id]];
    }
#endif
    [self.logFeed majorErrorText:[NSString stringWithFormat:@"SCTP sendfailed: len=%u err=%d\n", snp->sn_send_failed.ssf_length,snp->sn_send_failed.ssf_error]];
#if defined(POWER_DEBUG)
    NSLog(@"%@ SCTP_SEND_FAILED len=%u err=%d\n",_layerName,snp->sn_send_failed.ssf_length,snp->sn_send_failed.ssf_error);
#endif
    [self powerdownInReceiverThread:@"SCTP_SEND_FAILED"];
    [self reportStatus];
    return -1;
}


-(int) handleShutdownEvent:(NSData *)event
                  streamId:(NSNumber *)streamId
                protocolId:(NSNumber *)protocolId
{
#if defined(ULIBSCTP_CONFIG_DEBUG)
    const union sctp_notification *snp;
    snp = event.bytes;
#endif
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_SHUTDOWN_EVENT"];
    }
#endif
    if(len < sizeof (struct sctp_shutdown_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_SHUTDOWN_EVENT"];
#if defined(POWER_DEBUG)
        NSLog(@"%@  Size Mismatch in SCTP_SHUTDOWN_EVENT",_layerName);
#endif
        [self powerdownInReceiverThread:@"Size Mismatch in SCTP_SHUTDOWN_EVENT"];
        [self reportStatus];
        return UMSocketError_not_supported_operation;
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  sse_type: %d",     (int)snp->sn_shutdown_event.sse_type]];
        [self logDebug:[NSString stringWithFormat:@"  sse_flags: %d",    (int)snp->sn_shutdown_event.sse_flags]];
        [self logDebug:[NSString stringWithFormat:@"  sse_length: %d",   (int)snp->sn_shutdown_event.sse_length]];
        [self logDebug:[NSString stringWithFormat:@"  sse_assoc_id: %d", (int)snp->sn_shutdown_event.sse_assoc_id]];
    }
#endif
    [self.logFeed warningText:@"SCTP_SHUTDOWN_EVENT->POWERDOWN"];
    
#if defined(POWER_DEBUG)
    NSLog(@"%@  SCTP_SHUTDOWN_EVENT->POWERDOWN",_layerName);
#endif
    [self powerdownInReceiverThread:@"SCTP_SHUTDOWN_EVENT"];
    [self reportStatus];
    return -1;
}


-(int) handleAdaptionIndication:(NSData *)event
                       streamId:(NSNumber *)streamId
                     protocolId:(NSNumber *)protocolId
{
#if defined(ULIBSCTP_CONFIG_DEBUG)
    const union sctp_notification *snp;
    snp = event.bytes;
#endif
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_ADAPTATION_INDICATION"];
    }
#endif
    if(len < sizeof(struct sctp_adaptation_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_ADAPTATION_INDICATION"];
#if defined(POWER_DEBUG)
        NSLog(@"%@  Size Mismatch in SCTP_ADAPTATION_INDICATION",_layerName);
#endif
        [self powerdownInReceiverThread:@"Size mismatch in SCTP_ADAPTATION_INDICATION"];
        [self reportStatus];
        return UMSocketError_not_supported_operation;
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  sai_type: %d",           (int)snp->sn_adaptation_event.sai_type]];
        [self logDebug:[NSString stringWithFormat:@"  sai_flags: %d",          (int)snp->sn_adaptation_event.sai_flags]];
        [self logDebug:[NSString stringWithFormat:@"  sai_length: %d",         (int)snp->sn_adaptation_event.sai_length]];
        [self logDebug:[NSString stringWithFormat:@"  sai_adaptation_ind: %d", (int)snp->sn_adaptation_event.sai_adaptation_ind]];
        [self logDebug:[NSString stringWithFormat:@"  sai_assoc_id: %d",       (int)snp->sn_adaptation_event.sai_assoc_id]];
    }
#endif
    return 0;
}

-(int) handlePartialDeliveryEvent:(NSData *)event
                         streamId:(uint32_t)streamId
                       protocolId:(uint16_t)protocolId
{
#if defined(ULIBSCTP_CONFIG_DEBUG)
    const union sctp_notification *snp;
    snp = event.bytes;
#endif
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_PARTIAL_DELIVERY_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_pdapi_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_PARTIAL_DELIVERY_EVENT"];
#if defined(POWER_DEBUG)
        NSLog(@"%@  SCTP_PARTIAL_DELIVERY_EVENT",_layerName);
#endif

        [self powerdownInReceiverThread:@"Size mismatch in SCTP_PARTIAL_DELIVERY_EVENT"];
        [self reportStatus];
        return UMSocketError_not_supported_operation;
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  pdapi_type: %d",           (int)snp->sn_pdapi_event.pdapi_type]];
        [self logDebug:[NSString stringWithFormat:@"  pdapi_flags: %d",          (int)snp->sn_pdapi_event.pdapi_flags]];
        [self logDebug:[NSString stringWithFormat:@"  pdapi_length: %d",         (int)snp->sn_pdapi_event.pdapi_length]];
        [self logDebug:[NSString stringWithFormat:@"  pdapi_indication: %d",     (int)snp->sn_pdapi_event.pdapi_indication]];
#ifndef LINUX
        [self logDebug:[NSString stringWithFormat:@"  pdapi_stream: %d",         (int)snp->sn_pdapi_event.pdapi_stream]];
        [self logDebug:[NSString stringWithFormat:@"  pdapi_seq: %d",            (int)snp->sn_pdapi_event.pdapi_seq]];
#endif
        [self logDebug:[NSString stringWithFormat:@"  pdapi_assoc_id: %d",       (int)snp->sn_pdapi_event.pdapi_assoc_id]];
    }
#endif
    return UMSocketError_no_error;
}

-(int) handleAuthenticationEvent:(NSData *)event
                        streamId:(NSNumber *)streamId
                      protocolId:(NSNumber *)protocolId
{
#if defined(ULIBSCTP_CONFIG_DEBUG)
    const union sctp_notification *snp;
    snp = event.bytes;
#endif
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_AUTHENTICATION_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_authkey_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_AUTHENTICATION_EVENT"];
#if defined(POWER_DEBUG)
        NSLog(@"%@  Size Mismatch in SCTP_AUTHENTICATION_EVENT",_layerName);
#endif

        [self powerdownInReceiverThread:@"Size mismatch in SCTP_AUTHENTICATION_EVENT"];
        [self reportStatus];
        return UMSocketError_not_supported_operation;
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
#if defined(LINUX)
        [self logDebug:[NSString stringWithFormat:@"  auth_type: %d",           (int)snp->sn_authkey_event.auth_type]];
        [self logDebug:[NSString stringWithFormat:@"  auth_flags: %d",          (int)snp->sn_authkey_event.auth_flags]];
        [self logDebug:[NSString stringWithFormat:@"  auth_length: %d",         (int)snp->sn_authkey_event.auth_length]];
        [self logDebug:[NSString stringWithFormat:@"  auth_keynumber: %d",      (int)snp->sn_authkey_event.auth_keynumber]];
        [self logDebug:[NSString stringWithFormat:@"  auth_altkeynumber: %d",   (int)snp->sn_authkey_event.auth_altkeynumber]];
        [self logDebug:[NSString stringWithFormat:@"  auth_indication: %d",     (int)snp->sn_authkey_event.auth_indication]];
        [self logDebug:[NSString stringWithFormat:@"  auth_assoc_id: %d",       (int)snp->sn_authkey_event.auth_assoc_id]];

#else
        [self logDebug:[NSString stringWithFormat:@"  auth_type: %d",           (int)snp->sn_auth_event.auth_type]];
        [self logDebug:[NSString stringWithFormat:@"  auth_flags: %d",          (int)snp->sn_auth_event.auth_flags]];
        [self logDebug:[NSString stringWithFormat:@"  auth_length: %d",         (int)snp->sn_auth_event.auth_length]];
        [self logDebug:[NSString stringWithFormat:@"  auth_keynumber: %d",      (int)snp->sn_auth_event.auth_keynumber]];
        [self logDebug:[NSString stringWithFormat:@"  auth_altkeynumber: %d",   (int)snp->sn_auth_event.auth_altkeynumber]];
        [self logDebug:[NSString stringWithFormat:@"  auth_indication: %d",     (int)snp->sn_auth_event.auth_indication]];
        [self logDebug:[NSString stringWithFormat:@"  auth_assoc_id: %d",       (int)snp->sn_auth_event.auth_assoc_id]];
#endif
    }
#endif
    return UMSocketError_no_error;
}

#if defined(SCTP_STREAM_RESET_EVENT)
-(int) handleStreamResetEvent:(NSData *)event
                     streamId:(NSNumber *)streamId
                   protocolId:(NSNumber *)protocolId
{
#if defined(ULIBSCTP_CONFIG_DEBUG)
    const union sctp_notification *snp;
    snp = event.bytes;
#endif
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_STREAM_RESET_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_stream_reset_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_STREAM_RESET_EVENT"];
#if defined(POWER_DEBUG)
        NSLog(@"%@  Size Mismatch in SCTP_STREAM_RESET_EVENT",_layerName);
#endif

        [self powerdownInReceiverThread:@"Size mismatch in SCTP_STREAM_RESET_EVENT"];
        [self reportStatus];
        return UMSocketError_not_supported_operation;
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  strreset_type: %d",     (int)snp->sn_strreset_event.strreset_type]];
        [self logDebug:[NSString stringWithFormat:@"  strreset_flags: %d",    (int)snp->sn_strreset_event.strreset_flags]];
        [self logDebug:[NSString stringWithFormat:@"  strreset_length: %d",   (int)snp->sn_strreset_event.strreset_length]];
        [self logDebug:[NSString stringWithFormat:@"  strreset_assoc_id: %d", (int)snp->sn_strreset_event.strreset_assoc_id]];
    }
#endif
    [self setStatus:UMSOCKET_STATUS_OFF reason:@"handleStreamResetEvent"];
#if defined(POWER_DEBUG)
    NSLog(@"%@ handleStreamResetEvent",_layerName);
#endif
    [self reportStatus];
    return UMSocketError_no_error;
}
#endif

-(int) handleSenderDryEvent:(NSData *)event
                   streamId:(NSNumber *)streamId
                 protocolId:(NSNumber *)protocolId
{
#if defined(ULIBSCTP_CONFIG_DEBUG)
    const union sctp_notification *snp;
    snp = event.bytes;
#endif
    NSUInteger len = event.length;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_SENDER_DRY_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_sender_dry_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_SENDER_DRY_EVENT"];
#if defined(POWER_DEBUG)
    NSLog(@"%@ Size Mismatch in SCTP_SENDER_DRY_EVENT",_layerName);
#endif
        [self powerdownInReceiverThread:@"Size mismatch in SCTP_SENDER_DRY_EVENT"];
        [self reportStatus];
        return UMSocketError_not_supported_operation;
    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  sender_dry_type: %d",     (int)snp->sn_sender_dry_event.sender_dry_type]];
        [self logDebug:[NSString stringWithFormat:@"  sender_dry_flags: %d",    (int)snp->sn_sender_dry_event.sender_dry_flags]];
        [self logDebug:[NSString stringWithFormat:@"  sender_dry_length: %d",   (int)snp->sn_sender_dry_event.sender_dry_length]];
        [self logDebug:[NSString stringWithFormat:@"  sender_dry_assoc_id: %d", (int)snp->sn_sender_dry_event.sender_dry_assoc_id]];
    }
#endif
    return UMSocketError_no_error;
}


- (UMSocketError) sctpReceivedData:(NSData *)data
                          streamId:(NSNumber *)streamId
                        protocolId:(NSNumber *)protocolId
{
    @autoreleasepool
    {
        [_inboundThroughputPackets increaseBy:1];
        [_inboundThroughputBytes increaseBy:(int)data.length];

    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"RXT: got %u bytes on stream %u protocol_id: %u data:%@",
                            (unsigned int)data.length,
                            (unsigned int)streamId.unsignedIntValue,
                            (unsigned int)protocolId.unsignedIntValue,
                            data.hexString]];
        }
    #endif
        if(_defaultUser == NULL)
        {
            [self logDebug:@"RXT: USER instance not found. Maybe not bound yet?"];
#if defined(POWER_DEBUG)
            NSLog(@"%@ RXT: USER instance not found. Maybe not bound yet?",_layerName);
#endif
            [self powerdownInReceiverThread:@"USER instance not found. Maybe not bound yet"];
            [self reportStatus];
            return UMSocketError_no_buffers;
        }

        /* if for whatever reason we have not realized we are in service yet, let us realize it now */
        if(self.status!= UMSOCKET_STATUS_IS)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            if(self.logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"force change status to IS"]];
            }
    #endif
#if defined(POWER_DEBUG)
            NSLog(@"%@ receiving data: force change status to IS",_layerName);
#endif
            [self setStatus:UMSOCKET_STATUS_IS reason:@"sctpReceiveData"];
            [self reportStatus];
        }

        NSArray *usrs = [_users arrayCopy];
        for(UMLayerSctpUser *u in usrs)
        {
            if( [u.profile wantsProtocolId:protocolId]
               || [u.profile wantsStreamId:streamId])
            {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <= UMLOG_DEBUG)
                {
                    [self logDebug:[NSString stringWithFormat:@"passing data '%@' to USER[%@]",data.description,u.user.layerName]];
                }
    #endif
                [u.user sctpDataIndication:self
                                    userId:u.userId
                                  streamId:streamId.unsignedShortValue
                                protocolId:protocolId.unsignedIntValue
                                      data:data];
            }
            if([u.profile wantsMonitor])
            {
                [u.user sctpMonitorIndication:self
                                       userId:u.userId
                                     streamId:streamId.unsignedShortValue
                                   protocolId:protocolId.unsignedIntValue
                                         data:data
                                     incoming:YES];
            }
        }
        return UMSocketError_no_error;
    }
}

#pragma mark -
#pragma mark Config Handling
- (void)setConfig:(NSDictionary *)cfg applicationContext:(id<UMLayerSctpApplicationContextProtocol>)appContext
{
    @autoreleasepool
    {

        if(_registry==NULL)
        {
            NSLog(@"Error: configuring a SCTP object which does not have .registry initialized to a global UMSocketSCTPRegistry object");
            exit(0);
        }
        [self readLayerConfig:cfg];
        if(cfg[@"allow-any-remote-port-inbound"])
        {
            _allowAnyRemotePortIncoming = [cfg[@"allow-any-remote-port-inbound"] boolValue];
        }
        else
        {
            _allowAnyRemotePortIncoming = NO;
        }
        if (cfg[@"local-ip"])
        {
            id local_ip_object = cfg[@"local-ip"];
            if([local_ip_object isKindOfClass:[NSString class]])
            {
                NSString *line = (NSString *)local_ip_object;
                self.configured_local_addresses = [line componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t;"]];
            }
            else if([local_ip_object isKindOfClass:[UMSynchronizedArray class]])
            {
                UMSynchronizedArray *ua = (UMSynchronizedArray *)local_ip_object;
                self.configured_local_addresses = [ua.array copy];
            }
            else if([local_ip_object isKindOfClass:[UMSynchronizedArray class]])
            {
                UMSynchronizedArray *arr = (UMSynchronizedArray *)local_ip_object;
                self.configured_local_addresses = [arr arrayCopy];
            }
            else if([local_ip_object isKindOfClass:[NSArray class]])
            {
                NSArray *arr = (NSArray *)local_ip_object;
                self.configured_local_addresses = [arr copy];
            }
        }
        else
        {
            NSLog(@"Warning: no local-ip defined for sctp %@",self.layerName);
        }
        if (cfg[@"local-port"])
        {
            _configured_local_port = [cfg[@"local-port"] intValue];
        }
        if (cfg[@"remote-ip"])
        {
            id remote_ip_object = cfg[@"remote-ip"];
            if([remote_ip_object isKindOfClass:[NSString class]])
            {
                NSString *line = (NSString *)remote_ip_object;
                self.configured_remote_addresses = [line componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t;"]];
            }
            else if([remote_ip_object isKindOfClass:[UMSynchronizedArray class]])
            {
                UMSynchronizedArray *ua = (UMSynchronizedArray *)remote_ip_object;
                self.configured_remote_addresses = [ua.array copy];
            }
            else if([remote_ip_object isKindOfClass:[UMSynchronizedArray class]])
            {
                UMSynchronizedArray *arr = (UMSynchronizedArray *)remote_ip_object;
                self.configured_remote_addresses = [arr arrayCopy];
            }
            else if([remote_ip_object isKindOfClass:[NSArray class]])
            {
                NSArray *arr = (NSArray *)remote_ip_object;
                self.configured_remote_addresses = [arr copy];
            }
        }
        if (cfg[@"remote-port"])
        {
            _configured_remote_port = [cfg[@"remote-port"] intValue];
        }
        if (cfg[@"passive"])
        {
            _isPassive = [cfg[@"passive"] boolValue];
        }
        if (cfg[@"heartbeat"])
        {
            _heartbeatSeconds = [cfg[@"heartbeat"] doubleValue];
        }
        if (cfg[@"reconnect-timer"])
        {
            _reconnectTimerValue = [cfg[@"reconnect-timer"] doubleValue];
            _reconnectTimer.seconds = _reconnectTimerValue;
        }

        if ([cfg[@"sctp-over-tcp"] boolValue]==YES)
        {
            _encapsulatedOverTcp = YES;
        }
        if (cfg[@"sctp-over-tcp-session-key"])
        {
            _encapsulatedOverTcpSessionKey = [cfg[@"sctp-over-tcp-session-key"] stringValue];
        }
        if (cfg[@"mtu"])
        {
            _mtu = [cfg[@"mtu"] intValue];
        }
        else
        {
            _mtu = 1416; /* usually safer default  than 1500 due to ipsec */
        }
        if (cfg[@"dscp"])
        {
            _dscp = [cfg[@"dscp"] stringValue];
        }

        if (cfg[@"max-init-timeout"])
        {
            _maxInitTimeout = [cfg[@"max-init-timeout"] intValue];
        }
        else
        {
            _maxInitTimeout = 15; /* we send INIT every 15 sec */
        }
        
        if (cfg[@"max-init-attempts"])
        {
            _maxInitAttempts = [cfg[@"max-init-attempts"] intValue];
        }
        else
        {
            _maxInitAttempts = 12; /* we try up to 12 titmes (3 minutes at 15sec intervalls) */
        }
        if (cfg[@"min-receive-buffer-size"])
        {
            _minReceiveBufferSize = [cfg[@"min-receive-buffer-size"] intValue];
        }
        if (cfg[@"min-send-buffer-size"])
        {
            _minSendBufferSize = [cfg[@"min-send-buffer-size"] intValue];
        }
    #ifdef ULIB_SCTP_DEBUG
        if(_logLevel <=UMLOG_DEBUG)
        {
            NSLog(@"configured_local_addresses=%@",configured_local_addresses);
            NSLog(@"configured_remote_addresses=%@",configured_remote_addresses);
        }
    #endif
    }
}

- (NSDictionary *)config
{
    @autoreleasepool
    {
        NSMutableDictionary *config = [[NSMutableDictionary alloc]init];
        [self addLayerConfig:config];
        config[@"local-ip"] = [_configured_local_addresses componentsJoinedByString:@" "];
        config[@"local-port"] = @(_configured_local_port);
        config[@"remote-ip"] = [_configured_remote_addresses componentsJoinedByString:@" "];
        config[@"remote-port"] = @(_configured_remote_port);
        config[@"passive"] = _isPassive ? @YES : @ NO;
        config[@"heartbeat"] = @(_heartbeatSeconds);
        config[@"reconnect-timer"] = @(_reconnectTimerValue);
        config[@"heartbeat"] = @(_heartbeatSeconds);
        config[@"mtu"] = @(_mtu);
        if(_dscp)
        {
            config[@"dscp"] = _dscp;
        }
        config[@"max-init-timeout"] = @(_maxInitTimeout);
        config[@"max-init-attempts"] = @ (_maxInitAttempts);
        config[@"sctp-over-tcp"] = @(_encapsulatedOverTcp);
        return config;
    }
}

- (NSDictionary *)apiStatus
{
    @autoreleasepool
    {
        NSMutableDictionary *d = [[NSMutableDictionary alloc]init];
        switch(self.status)
        {
            case UMSOCKET_STATUS_FOOS:
                d[@"status"] = @"M-FOOS";
                break;
            case UMSOCKET_STATUS_OFF:
                d[@"status"] = @"OFF";
                break;
            case UMSOCKET_STATUS_OOS:
                d[@"status"] = @"OOS";
                break;
            case UMSOCKET_STATUS_IS:
                d[@"status"] = @"IS";
                break;
            default:
                d[@"status"] = [NSString stringWithFormat:@"unknown(%d)",self.status];
                break;
        }
        d[@"name"] = self.layerName;
        
        d[@"configured-local-port"] = @(_configured_local_port);
        d[@"configured-remote-port"] = @(_configured_remote_port);
        d[@"active-local-port"] = @(_active_local_port);
        d[@"active-remote-port"] = @(_active_remote_port);

        if(_configured_local_addresses.count > 0)
        {
            d[@"configured-local-addresses"] = [_configured_local_addresses copy];
        }
        if(_configured_remote_addresses.count>0)
        {
            d[@"configured-remote-addresses"] = [_configured_remote_addresses copy];
        }
        if(_active_local_addresses.count)
        {
            d[@"active-local-addresses"] = [_active_local_addresses copy];
        }
        if(_active_remote_addresses.count)
        {
            d[@"active-remote-addresses"] = [_active_remote_addresses copy];
        }
        d[@"is-passive"] = _isPassive ? @(YES) : @(NO);
        d[@"poll-timeout-in-ms"] = @(_timeoutInMs);
        d[@"heartbeat"] = @(_heartbeatSeconds);
        d[@"mtu"] = @(_mtu);
        if(_dscp)
        {
            d[@"dscp"] = _dscp;
        }
        return d;
    }
}

- (void)stopDetachAndDestroy
{
    /* FIXME: do something here */
}

- (NSString *)statusString
{
    return [UMSocket statusDescription:self.status];
}

-(void)dealloc
{
    if(_listenerStarted==YES)
    {
        [_listener stopListeningFor:self];
    }
    _listener = NULL;
}

- (void)reconnectTimerFires
{
    @autoreleasepool
    {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@"reconnectTimerFires"];
        }
    #endif
        [_reconnectTimer stop];
        if(_isPassive)
        {
            [_listener startListeningFor:self];
            _listenerStarted = _listener.isListening;
        }
        else
        {
            if(self.status != UMSOCKET_STATUS_IS)
            {
                NSNumber *xassocId = NULL;
                [_listener connectToAddresses:_configured_remote_addresses
                                         port:_configured_remote_port
                                     assocPtr:&xassocId
                                        layer:self];
                if(xassocId != NULL)
                {
                    _assocId = xassocId;
                }
                [_registry registerAssoc:_assocId forLayer:self];
            }
        }
    }
}

- (void)processError:(UMSocketError)err socket:(UMSocket *)socket inArea:(NSString *)area
{
    if(err==UMSocketError_no_data)
    {
       return;
    }
    if(err==UMSocketError_no_error)
    {
        return;
    }
    @autoreleasepool
    {
        if(_logLevel <=UMLOG_MINOR)
        {
            NSLog(@"processError %d %@ received in UMLayerSctp %@",err, [UMSocket getSocketErrorString:err], _layerName);
        }
#if defined(POWER_DEBUG)
            NSLog(@"%@ processError: %d %@",_layerName,err, [UMSocket getSocketErrorString:err]);
#endif
        if(err==UMSocketError_invalid_file_descriptor)
        {
            if(_directSocket == socket)
            {
                _directSocket = NULL;
                NSString *s = [NSString stringWithFormat:@"processError(%d,%@) inArea %@",err,[UMSocket getSocketErrorString:err],area];
                [self setStatus:UMSOCKET_STATUS_OOS reason:s];
                [self setStatus:UMSOCKET_STATUS_OFF reason:s];
                [_registry unregisterAssoc:_assocId];
                _assocId = NULL;
                [_registry unregisterLayer:self];
                [self reportStatus];
            }
            else
            {
                NSString *s = [NSString stringWithFormat:@"got error UMSocketError_invalid_file_descriptor on socket %p (%d) but _directSocket is %p (%d). Ignoring",socket,socket.sock,_directSocket,_directSocket.sock];
                [_layerHistory addLogEntry:s];
            }
        }
        else
        {
            [self powerdown:[NSString stringWithFormat:@"processError %d %@",err,[UMSocket getSocketErrorString:err]]];
            [self reportStatus];
        }
    }
}

- (void)processHangUp
{
    @autoreleasepool
    {
        if(_logLevel <=UMLOG_DEBUG)
        {
            NSLog(@"processHangUp received in UMLayerSctp %@",_layerName);
        }
#if defined(POWER_DEBUG)
            NSLog(@"%@ processHangUp",_layerName);
#endif
        [self powerdown:@"processHangUp"];
        [self reportStatus];
    }
}

- (void)processInvalidSocket
{
    @autoreleasepool
    {
        if(_logLevel <=UMLOG_DEBUG)
        {
            NSLog(@"processInvalidSocket received in UMLayerSctp %@",_layerName);
        }
        _isInvalid = YES;
#if defined(POWER_DEBUG)
        NSLog(@"%@ processInvalidSocket",_layerName);
#endif
        [self powerdown:@"processInvalidSocket"];
        [self reportStatus];
    }
}




- (ssize_t) sendEncapsulated:(NSData *)data
                       assoc:(NSNumber *)assoc
                     stream:(NSNumber *)streamId
                   protocol:(NSNumber *)protocolId
                      error:(UMSocketError *)err2
                       flags:(int)flags
{
    UMSocketError err = UMSocketError_no_error;

    sctp_over_tcp_header header;
    memset(&header,0,sizeof(header));
    header.header_length = htonl(sizeof(header));
    header.payload_length = htonl(data.length);
    header.protocolId = htonl(protocolId.unsignedLongValue);
    header.streamId = htons(streamId.unsignedShortValue);
    header.flags = htons(flags);

    
    NSMutableData *data2 = [[NSMutableData alloc]initWithBytes:&header length:sizeof(header)];
    if(data)
    {
        [data2 appendData:data];
    }
    err = [_directTcpEncapsulatedSocket sendData:data2];
    
    if(err2)
    {
        *err2 = err;
    }
    if(err == UMSocketError_no_error)
    {
        return data2.length;
    }
    return -1;
}

- (BOOL)isPathMtuDiscoveryEnabled
{
    return _directSocket.isPathMtuDiscoveryEnabled;
}

- (int)currentMtu
{
    return _directSocket.currentMtu;
}


- (UMSynchronizedSortedDictionary *)sctpStatusDict
{
    UMSynchronizedSortedDictionary *dict = [[UMSynchronizedSortedDictionary alloc]init];
    
    dict[@"name"] = self.layerName;
    dict[@"listener"] = _listener.name;
    if(_directSocket)
    {
        dict[@"direct-socket"] = [_directSocket description];
    }
    else
    {
        dict[@"direct-socket"] = @"(null)";
    }
    dict[@"configured-local-port"] = @(_configured_local_port);
    dict[@"configured-remote-port"] = @(_configured_remote_port);
    dict[@"active-local-port"] = @(_active_local_port);
    dict[@"active-remote-port"] = @(_active_remote_port);

    if(_configured_local_addresses)
    {
        dict[@"configured-local-addresses"] = _configured_local_addresses;
    }
    if(_configured_remote_addresses)
    {
        dict[@"configured-remote-addresses"] = _configured_remote_addresses;
    }
    if(_active_local_addresses)
    {
        dict[@"active-local-addresses"] = _active_local_addresses;
    }
    if(_active_remote_addresses)
    {
        dict[@"active-remote-addresses"] = _active_remote_addresses;
    }
    if(_reconnectTimer)
    {
        dict[@"reconnect-timer"] = [_reconnectTimer timerDescription];
    }
    dict[@"reconnect-timer-value"] = @(_reconnectTimerValue);
    dict[@"heartbeat-seconds"] = @(_heartbeatSeconds);

    dict[@"poll-timeout"] = @(_timeoutInMs/1000.0);
    dict[@"passive"] = @(_isPassive);
    if(_dscp)
    {
        dict[@"dscp"] = _dscp;
    }
    dict[@"listener-started"] = @(_listenerStarted);
    dict[@"is-invalid"] = @(_isInvalid);
    dict[@"new-Destination"] = @(_newDestination);
    dict[@"max-init-timeout"] = @(_maxInitTimeout);
    dict[@"max-init-attempts"] = @(_maxInitAttempts);

    switch(self.status)
    {
        case UMSOCKET_STATUS_FOOS:
            dict[@"sctp-socket-status"] = @"UMSOCKET_STATUS_FOOS";
            break;
        case UMSOCKET_STATUS_OFF:
            dict[@"sctp-socket-status"] = @"UMSOCKET_STATUS_OFF";
            break;
        case UMSOCKET_STATUS_OOS:
            dict[@"sctp-socket-status"] = @"UMSOCKET_STATUS_OOS";
            break;
        case UMSOCKET_STATUS_IS:
            dict[@"sctp-socket-status"] = @"UMSOCKET_STATUS_IS";
            break;
        case UMSOCKET_STATUS_LISTENING:
            dict[@"sctp-socket-status"] = @"UMSOCKET_STATUS_LISTENING";
            break;
    }
    dict[@"encapsualted-over-tcp"] = @(_encapsulatedOverTcp);
    if(_encapsulatedOverTcpSessionKey)
    {
        dict[@"encapsualted-over-tcp-session-key"] = _encapsulatedOverTcpSessionKey;
    }
    dict[@"min-receive-buffer-size"] = @(_minReceiveBufferSize);
    dict[@"min-send-buffer-size"] = @(_minSendBufferSize);
    
    NSMutableArray *a = [[NSMutableArray alloc]init];
    for(UMLayerSctpUser *u in _users)
    {
        UMSynchronizedSortedDictionary *dict = [[UMSynchronizedSortedDictionary alloc]init];
        dict[@"name"] = u.user.layerName;
        [a addObject:dict];
    }
    dict[@"users"] = a;
    dict[@"last-events"] = [_layerHistory getLogArrayWithDatesAndOrder:YES];
    return dict;
}


-(void)setStatus:(UMSocketStatus)s reason:(NSString *)reason
{
    UMSocketStatus oldStatus = _status;
    _status = s;
    if(oldStatus != _status)
    {
        [self reportStatus];
        [self addToLayerHistoryLog:[NSString stringWithFormat:@"status change from %@ to %@ because of %@",
                        [UMLayerSctp socketStatusString:oldStatus],
                        [UMLayerSctp socketStatusString:_status],reason ] ];
    }
}

-(UMSocketStatus)status
{
    return _status;
}

+(NSString *)socketStatusString:(UMSocketStatus)s
{
    switch(s)
    {
        case UMSOCKET_STATUS_FOOS:
            return @"M-FOOS";
        case UMSOCKET_STATUS_OFF:
            return  @"OFF";
        case UMSOCKET_STATUS_OOS:
            return @"OOS";
            break;
        case UMSOCKET_STATUS_IS:
            return @"IS";
        default:
            return @"(bogous)";
            break;
    }
}
@end
