//
//  UMLayerSctp.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#define ULIBSCTP_INTERNAL 1

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

#include "ulibsctp_config.h"

#ifdef HAVE_SCTP_SCTP_H
#import <sctp/sctp.h>
#endif

#ifdef HAVE_NETINET_SCTP_H
#include "netinet/sctp.h"
#endif


#import "UMLayerSctpUser.h"
#import "UMSctpOverTcp.h"


@implementation UMLayerSctp

- (UMLayerSctp *)init
{
    self = [self initWithTaskQueueMulti:NULL name:@"sctp-dummy"];
    if(self)
    {
        _newDestination = YES;
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
        self.status = UMSOCKET_STATUS_OFF;
        _newDestination = YES;
        _inboundThroughputPackets   = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _inboundThroughputBytes     = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _outboundThroughputPackets  = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _outboundThroughputBytes    = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _reconnectTimerValue = 6.0;
        _reconnectTimer = [[UMTimer alloc]initWithTarget:self selector:@selector(reconnectTimerFires) object:NULL seconds:_reconnectTimerValue name:@"reconnect-timer" repeats:NO runInForeground:YES];
        NSString *lockName = [NSString stringWithFormat:@"sctp-layer-link-lock(%@)",name];
        _linkLock = [[UMMutex alloc]initWithName:lockName];

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
    [self openFor:caller sendAbortFirst:NO];
}

- (void)openFor:(id<UMLayerSctpUserProtocol>)caller sendAbortFirst:(BOOL)abortFirst
{
    UMSctpTask_Open *task = [[UMSctpTask_Open alloc]initWithReceiver:self sender:caller];
    task.sendAbortFirst = abortFirst;
    [self queueFromUpper:task];
}

- (void)closeFor:(id<UMLayerSctpUserProtocol>)caller
{
    UMSctpTask_Close *task =
    [[UMSctpTask_Close alloc]initWithReceiver:self sender:caller];
    [self queueFromUpper:task];
   
}

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
                                        streamId:sid
                                      protocolId:pid
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
    @autoreleasepool
    {
        UMSctpTask_Manual_ForceOutOfService *task =
        [[UMSctpTask_Manual_ForceOutOfService alloc]initWithReceiver:self sender:caller];
        [self queueFromLowerWithPriority:task];
    }
}

- (void)isFor:(id<UMLayerSctpUserProtocol>)caller
{
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
        uint32_t        tmp_assocId = -1;
        BOOL sendAbort = task.sendAbortFirst;
        
        id<UMLayerUserProtocol> caller = task.sender;

        if(self.logLevel <= UMLOG_DEBUG)
        {
            NSString *s = [NSString stringWithFormat:@"%@ is asking us to start SCTP %@->%@",caller.layerName,_configured_local_addresses,_configured_remote_addresses];
            [self logDebug:s];
        }

        [_linkLock lock];

        @try
        {
            if(self.status == UMSOCKET_STATUS_FOOS)
            {
                NSLog(@"UMSOCKET_STATUS_FOOS"); 
                @throw([NSException exceptionWithName:@"FOOS" reason:@"failed due to manual forced out of service status" userInfo:@{@"errno":@(EBUSY), @"backtrace": UMBacktrace(NULL,0)}]);
            }
            if(self.status == UMSOCKET_STATUS_OOS)
            {
                [self logMinorError:@"already establishing"];
                @throw([NSException exceptionWithName:@"OOS" reason:@"status is OOS so SCTP is already establishing." userInfo:@{@"errno":@(EINPROGRESS),@"backtrace": UMBacktrace(NULL,0)}]);
            }
            if(self.status == UMSOCKET_STATUS_IS)
            {
                [self logMinorError:@"already in service"];
                NSLog(@"UMSOCKET_STATUS_IS");
                @throw([NSException exceptionWithName:@"IS" reason:@"status is IS so already up." userInfo:@{@"errno":@(EAGAIN),@"backtrace": UMBacktrace(NULL,0)}]);
            }
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            if(self.logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"socket()"]];
            }
    #endif
            UMSocketError err = UMSocketError_no_error;

            if(self.logLevel <= UMLOG_DEBUG)
            {
                NSString *addrs = [_configured_local_addresses componentsJoinedByString:@","];
                [self logDebug:[NSString stringWithFormat:@"getting listener on %@ on port %d",addrs,_configured_local_port]];
            }
            if(_encapsulatedOverTcp)
            {
                if(_isPassive)
                {
                    _listener = [_registry getOrAddTcpListenerForPort:_configured_local_port];
                }
                else
                {
                    _listener = NULL;
                }
            }
            else
            {
                _listener =  [_registry getOrAddListenerForPort:_configured_local_port localIps:_configured_local_addresses];
            }
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
            if(_encapsulatedOverTcp)
            {
               if(_isPassive)
               {
                   [_listener startListeningFor:self]; /* FIXME: what if we have an error */
                   _listenerStarted = _listener.isListening;
               }
            }
            else
            {
                [_listener startListeningFor:self];
                _listenerStarted = _listener.isListening;
            }
            _newDestination = YES;
            sleep(1);
            _assocId = -1;
            _assocIdPresent = NO;
            
            if(!_isPassive)
            {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <= UMLOG_DEBUG)
                {
                    NSString *addrs = [_configured_remote_addresses componentsJoinedByString:@","];
                    [self logDebug:[NSString stringWithFormat:@"asking listener to connect to %@ on port %d",addrs,_configured_remote_port]];
                }
    #endif
                if(_encapsulatedOverTcp)
                {
                    if(_directTcpEncapsulatedSocket != NULL)
                    {
                       [_directTcpEncapsulatedSocket close];
                    }
#if defined(ULIBSCTP_CONFIG_DEBUG)
                    [self logDebug:@"_directTcpEncapsulatedSocket==NULL"];
#endif

                    tmp_assocId = -1;
                    if(_configured_remote_addresses.count < 0)
                    {
                        err = UMSocketError_invalid_port_or_address;
                    }
                    else
                    {
                        UMHost *lhost = [[UMHost alloc]initWithLocalhost];
                        UMHost *host = [[UMHost alloc]initWithAddress:_configured_remote_addresses[0]];
                        _directTcpEncapsulatedSocket = [[UMSocket alloc]initWithType:UMSOCKET_TYPE_TCP];
                        [_directTcpEncapsulatedSocket setLocalHost:lhost];
                        [_directTcpEncapsulatedSocket setLocalPort:_configured_local_port];
                        [_directTcpEncapsulatedSocket setRemoteHost:host];
                        [_directTcpEncapsulatedSocket setRemotePort:_configured_remote_port];
                    
                        
                        err = [_directTcpEncapsulatedSocket connect];
                        if(err == 0)
                        {
                            tmp_assocId = _directTcpEncapsulatedSocket.sock;
                            [self sendEncapsulated:[_encapsulatedOverTcpSessionKey dataValue]
                                             assoc:&tmp_assocId
                                            stream:0
                                          protocol:0
                                             error:&err
                                             flags:SCTP_OVER_TCP_SETUP | SCTP_OVER_TCP_NOTIFICATION];
                            self.status = UMSOCKET_STATUS_OOS;
                            [self reportStatus];
                        }
                        tmp_assocId = _directTcpEncapsulatedSocket.sock;
                    }
                    if((err == UMSocketError_no_error) || (err==UMSocketError_in_progress))
                    {
                        if(tmp_assocId != -1)
                        {
                            _assocId = tmp_assocId;
                            if((err != UMSocketError_no_error)
                            && (err !=UMSocketError_in_progress))
                            {
                                [_directTcpEncapsulatedSocket close];
                                _directTcpEncapsulatedSocket = NULL;
                            }
                        }
                    }
                }
                else
                {
                    if((_directSocket==NULL) && (_directTcpEncapsulatedSocket==NULL))
                    {
        #if defined(ULIBSCTP_CONFIG_DEBUG)
                        [self logDebug:@"_directSocket==NULL"];
        #endif

                        tmp_assocId = -1;
                        err = [_listener connectToAddresses:_configured_remote_addresses
                                                       port:_configured_remote_port
                                                      assoc:&tmp_assocId
                                                      layer:self];
                        if((err == UMSocketError_no_error) || (err==UMSocketError_in_progress))
                        {
                            if(tmp_assocId != -1)
                            {
                                _assocId = tmp_assocId;

        #if defined(ULIBSCTP_CONFIG_DEBUG)
                                [self logDebug:[NSString stringWithFormat:@"Peeling of assoc %lu",(unsigned long)tmp_assocId]];
        #endif
                                _directSocket = [_listener peelOffAssoc:_assocId error:&err];
        #if defined(ULIBSCTP_CONFIG_DEBUG)
                                [self logDebug:[NSString stringWithFormat:@"directSocket is now %d", (int)_directSocket.sock]];
        #endif

                                if((err != UMSocketError_no_error)
                                && (err !=UMSocketError_in_progress))
                                {
                                    [_directSocket close];
                                    _directSocket = NULL;
                                }
                            }
                        }
                    }
                    else
                    {
        #if defined(ULIBSCTP_CONFIG_DEBUG)
                        [self logDebug:[NSString stringWithFormat:@" using _directSocket"]];
        #endif
                        if(sendAbort)
                        {
                            for(NSString *addr in _configured_remote_addresses)
                            {
                                @try
                                {
                                    uint32_t a=0;
                                    if(_assocId > 0)
                                    {
                                        a = _assocId;
                                    }
                                    [_listener.umsocket abortToAddress:addr
                                                                  port:_configured_remote_port
                                                                 assoc:a
                                                                stream:0
                                                              protocol:0];
                                }
                                @catch(NSException *e)
                                {
                                }
                            }
                        }
                        err = [_directSocket connectToAddresses:_configured_remote_addresses
                                                            port:_configured_remote_port
                                                           assoc:&tmp_assocId];
                        if(tmp_assocId != -1)
                        {
                            _assocId = tmp_assocId;
                        }
                    }

                    if(_assocId!= -1)
                    {
                        _assocIdPresent = YES;
                    }
                    if(self.logLevel <= UMLOG_DEBUG)
                    {
                        NSString *e = [UMSocket getSocketErrorString:err];
                        [self logDebug:[NSString stringWithFormat:@"returns %d %@",err,e]];
                    }
                }
            }
            if(_encapsulatedOverTcp)
            {
                if(_isPassive == NO)
                {
                    [_registry registerOutgoingTcpLayer:self];
                }
                else
                {
                    if(_encapsulatedOverTcpSessionKey)
                    {
                        [_registry registerSessionKey:_encapsulatedOverTcpSessionKey forLayer:self];
                    }
                }
            }
            else
            {
                [_registry registerOutgoingLayer:self allowAnyRemotePortIncoming:_allowAnyRemotePortIncoming];
            }
            if ((err == UMSocketError_in_progress) || (err == UMSocketError_no_error))
            {
                self.status = UMSOCKET_STATUS_OOS;
            }
            if(_allowAnyRemotePortIncoming)
            {
                [_registry registerIncomingLayer:self];
            }
            if(_assocIdPresent)
            {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
                [self logDebug:[NSString stringWithFormat:@" registering new assoc"]];
    #endif
                [_registry registerAssoc:@(_assocId) forLayer:self];
            }
            [_registry startReceiver];
        }
        @catch (NSException *exception)
        {
            NSNumber *e = exception.userInfo[@"errno"];
            int err = e.intValue;
 //  #if defined(ULIBSCTP_CONFIG_DEBUG)
            if(self.logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"%@ %@",exception.name,exception.reason]];
            }
 //   #endif
            if(exception.userInfo)
            {
                if(e)
                {
                    [self logMajorError:[NSString stringWithFormat:@"%@ %@",exception.name,exception.reason]];
                }
            }
            if(err != EINPROGRESS)
            {
                [self powerdown];
            }
        }
        [_linkLock unlock];
        [self reportStatus];
    }
}

- (void)_closeTask:(UMSctpTask_Close *)task
{
    @autoreleasepool
    {
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
            [self powerdown];
            if(_listenerStarted==YES)
            {
                [_listener stopListeningFor:self];
            }
            _listener = NULL;
        }
        @catch(NSException *e)
        {
            NSLog(@"%@",e);
        }
        [_linkLock unlock];
        [self reportStatus];
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
            [self logDebug:[NSString stringWithFormat:@" streamId: %u",task.streamId]];
            [self logDebug:[NSString stringWithFormat:@" protocolId: %u",task.protocolId]];
            [self logDebug:[NSString stringWithFormat:@" ackRequest: %@",(task.ackRequest ? task.ackRequest.description  : @"(not present)")]];
        }
    #endif
        BOOL failed = NO;

        @try
        {
            if(task.data == NULL)
            {
                @throw([NSException exceptionWithName:@"NULL" reason:@"trying to send NULL data" userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
            }
            UMSocketError err = UMSocketError_no_error;

            ssize_t sent_packets = 0;
            
            int attempts=0;
            
            /* we try to send as long as no ASSOC down has been received or at least once (as we might not have a direct socket yet */
            int maxatt = 50;
            while((attempts < maxatt) ||  (self.status==UMSOCKET_STATUS_IS))
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
                    uint32_t        tmp_assocId = _assocId;
                    sent_packets = [_directSocket sendToAddresses:_configured_remote_addresses
                                                             port:_configured_remote_port
                                                            assoc:&tmp_assocId
                                                             data:task.data
                                                           stream:task.streamId
                                                         protocol:task.protocolId
                                                            error:&err];
                    _assocId = tmp_assocId;

                }
                else if(_directTcpEncapsulatedSocket)
                {
                    uint32_t tmp_assocId = _assocId;
                    [self sendEncapsulated:task.data
                                     assoc:&tmp_assocId
                                    stream:task.streamId
                                  protocol:task.protocolId
                                     error:&err
                                     flags:0];
                }
                else
                {
                    uint32_t tmp_assocId = _assocId;
                    sent_packets = [_listener sendToAddresses:_configured_remote_addresses
                                                         port:_configured_remote_port
                                                        assoc:&tmp_assocId
                                                         data:task.data
                                                       stream:task.streamId
                                                     protocol:task.protocolId
                                                        error:&err
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
                if(errno != EAGAIN)
                {
                    failed=YES;
                    break;
                }
                if(errno == EAGAIN)
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
                                             streamId:task.streamId
                                           protocolId:task.protocolId
                                                 data:task.data
                                             incoming:NO];
                    }
                }
                NSDictionary *ui = @{
                                     @"protocolId" : @(task.protocolId),
                                     @"streamId"   : @(task.streamId),
                                     @"data"       : task.data
                                     };
                NSMutableDictionary *report = [task.ackRequest mutableCopy];
                [report setObject:ui forKey:@"sctp_data"];
                //report[@"backtrace"] = UMBacktrace(NULL,0);
                [user sentAckConfirmFrom:self
                                userInfo:report];
                
            }
            else
            {
                NSLog(@"Error %d %s",errno,strerror(errno));
                if(errno==EISCONN)
                {
                    NSLog(@"already connected");
                }
                switch(errno)
                {
                    case 0:
                        break;
                        @throw([NSException exceptionWithName:@"ERROR-ZERO"
                                                       reason:@"send returns no error. weird"
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case EBADF:
                        @throw([NSException exceptionWithName:@"EBADF"
                                                       reason:@"An invalid descriptor was specified"
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case ENOTSOCK:
                        @throw([NSException exceptionWithName:@"ENOTSOCK"
                                                       reason:@"The argument s is not a socket"
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case EFAULT:
                        @throw([NSException exceptionWithName:@"EFAULT"
                                                       reason:@"An invalid user space address was specified"
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case EMSGSIZE:
                        @throw([NSException exceptionWithName:@"EMSGSIZE"
                                                       reason:@"The socket requires that message be sent atomically, and the size of the message to be sent made this impossible."
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case EAGAIN:
                        @throw([NSException exceptionWithName:@"EAGAIN"
                                                       reason:@"Resource temporarily unavailable"
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case ENOBUFS:
                        @throw([NSException exceptionWithName:@"ENOBUFS"
                                                       reason:@"The system was unable to allocate an internal buffer. The operation may succeed when buffers become available."
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case EACCES:
                        @throw([NSException exceptionWithName:@"EACCES"
                                                       reason:@"The SO_BROADCAST option is not set on the socket, and a broadcast address was given as the destination."
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case EHOSTUNREACH:
                        @throw([NSException exceptionWithName:@"EHOSTUNREACH"
                                                       reason:@"The destination address specified an unreachable host."
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case ENOTCONN:
                        @throw([NSException exceptionWithName:@"ENOTCONN"
                                                       reason:@"socket is not connected."
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case EPIPE:
                        @throw([NSException exceptionWithName:@"EPIPE"
                                                       reason:@"pipe is broken."
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case ECONNRESET:
                        @throw([NSException exceptionWithName:@"ECONNRESET"
                                                       reason:@"connection is reset by peer."
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                    case EADDRNOTAVAIL:
                        @throw([NSException exceptionWithName:@"EADDRNOTAVAIL"
                                                       reason:@"address is no available"
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                    default:
                        @throw([NSException exceptionWithName:[NSString stringWithFormat:@"ERROR %d",errno]
                                                       reason:[NSString stringWithFormat:@"unknown error %d %s",errno,strerror(errno)]
                                                     userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                        break;
                }
            }
        }
        @catch (NSException *exception)
        {
            if(linkLocked)
            {
                [_linkLock unlock];
            }
            [self logMajorError:[NSString stringWithFormat:@"%@: %@",exception.name,exception.reason]];
            if(task.ackRequest)
            {
                NSMutableDictionary *report = [task.ackRequest mutableCopy];
                NSDictionary *ui = @{
                                     @"protocolId" : @(task.protocolId),
                                     @"streamId"   : @(task.streamId),
                                     @"data"       : task.data
                                     };
                [report setObject:ui forKey:@"sctp_data"];
                
                NSDictionary *errDict = @{
                                          @"exception"  : exception.name,
                                          @"reason"     : exception.reason,
                                          };
                [report setObject:errDict forKey:@"sctp_error"];
                [user sentAckFailureFrom:self
                                userInfo:report
                                   error:exception.name
                                  reason:exception.reason
                               errorInfo:errDict];
            }
            [self powerdown];
        }
        [self reportStatus];
    }
}

- (void)_foosTask:(UMSctpTask_Manual_ForceOutOfService *)task
{
    @autoreleasepool
    {
        [_linkLock lock];
        [self powerdown];
        self.status = UMSOCKET_STATUS_FOOS;
    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <=UMLOG_DEBUG)
        {
            [self logDebug:@"FOOS"];
        }
    #endif
        [_linkLock unlock];
        [self reportStatus];
    }
}

- (void)_isTask:(UMSctpTask_Manual_InService *)task
{
    @autoreleasepool
    {
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
                self.status = UMSOCKET_STATUS_OFF;
                [self reportStatus];
                [self openFor:user sendAbortFirst:NO];
                break;
            case UMSOCKET_STATUS_OFF:
    #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <=UMLOG_DEBUG)
                {
                    [self logDebug:@"manual OFF->IS requested"];
                }
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
                [self reportStatus];
                break; 
            case UMSOCKET_STATUS_LISTENING:
            #if defined(ULIBSCTP_CONFIG_DEBUG)
                if(self.logLevel <=UMLOG_DEBUG)
                {
                    [self logDebug:@"manual LISTENING->IS requested"];
                }
            #endif
                [self reportStatus];
                break;
        }
    }
}


#pragma mark -
#pragma mark Helpers

- (void) powerdown
{
    @autoreleasepool
    {

    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self.logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
        }
    #endif
        //[_receiverThread shutdownBackgroundTask];
        self.status = UMSOCKET_STATUS_OOS;
        self.status = UMSOCKET_STATUS_OFF;
        if(_assocIdPresent)
        {
            [_registry unregisterAssoc:@(_assocId)];
            _assocId = -1;
            _assocIdPresent = NO;
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
    @autoreleasepool
    {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self.logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
        }
    #endif
        self.status = UMSOCKET_STATUS_OFF;
        if(_assocIdPresent)
        {
            [_registry unregisterAssoc:@(_assocId)];
            _assocId = -1;
            _assocIdPresent = NO;
        }
        [_directSocket close];
        _directSocket = NULL;
    }
}

- (void) reportStatus
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
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSMutableString *s = [[NSMutableString alloc]init];
        [s appendFormat:@"processReceivedData: \n%@",rx.description];
        [self logDebug:s];
#endif
        if(rx.assocId !=NULL)
        {
            if((_assocId == -1) || (_assocIdPresent == NO) || (_directSocket == NULL))
            {
                _assocId = (uint32_t)[rx.assocId unsignedLongValue];
                _assocIdPresent = YES;
            }
        }
        if((_directSocket == NULL) && (!_encapsulatedOverTcp))
        {
#if defined(ULIBSCTP_CONFIG_DEBUG)
            [self logDebug:[NSString stringWithFormat:@"Peeling of assoc %lu",(unsigned long)_assocId]];
#endif
            UMSocketError err = UMSocketError_no_error;
            _directSocket = [_listener peelOffAssoc:_assocId error:&err];
#if defined(ULIBSCTP_CONFIG_DEBUG)
            [self logDebug:[NSString stringWithFormat:@"directSocket is now %d", (int)_directSocket.sock]];
#endif
            if((err != UMSocketError_no_error) && (err !=UMSocketError_in_progress))
            {
                [_directSocket close];
                _directSocket = NULL;
            }
        }
        if(rx.err==UMSocketError_try_again)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"receiveData: UMSocketError_try_again returned by receiveSCTP");
    #endif
        }

        else if(rx.err==UMSocketError_connection_reset)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"receiveData: UMSocketError_connection_reset returned by receiveSCTP");
    #endif
            [self logDebug:@"ECONNRESET"];
            [self powerdownInReceiverThread];
            [self reportStatus];
        }

        else if(rx.err==UMSocketError_connection_aborted)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"receiveData: UMSocketError_connection_aborted returned by receiveSCTP");
    #endif
            [self logDebug:@"ECONNABORTED"];
            [self powerdownInReceiverThread];
            [self reportStatus];
        }
        else if(rx.err==UMSocketError_connection_refused)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"receiveData: UMSocketError_connection_refused returned by receiveSCTP");
    #endif
            [self logDebug:@"ECONNREFUSED"];
            sleep(1);
            [self powerdownInReceiverThread];
            [self reportStatus];
        }
        else if(rx.err != UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"receiveData: Error %d %@ returned by receiveSCTP",rx.err,[UMSocket getSocketErrorString:rx.err]]];
            [self powerdownInReceiverThread];
            [self reportStatus];
        }
        else
        {
            if(rx.flags & SCTP_OVER_TCP_SETUP_CONFIRM)
            {
                self.status = UMSOCKET_STATUS_IS;
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
           streamId:(uint32_t)streamId
         protocolId:(uint16_t)protocolId
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
                [self.logFeed majorErrorText:[NSString stringWithFormat:@" RX-STREAM: %d",streamId]];
                [self.logFeed majorErrorText:[NSString stringWithFormat:@" RX-PROTO: %d", protocolId]];
                [self.logFeed majorErrorText:[NSString stringWithFormat:@" RX-DATA: %@",event.description]];
        }
    }
}


-(void) handleAssocChange:(NSData *)event
                 streamId:(uint32_t)streamId
               protocolId:(uint16_t)protocolId
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
#if defined(ULIBSCTP_CONFIG_DEBUG)
    if(self.logLevel <= UMLOG_DEBUG)
    {
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
        _assocId = snp->sn_assoc_change.sac_assoc_id;
        _assocIdPresent=YES;
        [self.logFeed infoText:[NSString stringWithFormat:@" SCTP_ASSOC_CHANGE: SCTP_COMM_UP->IS (assocID=%ld)",(long)_assocId]];
        self.status = UMSOCKET_STATUS_IS;
        if(_directSocket==NULL)
        {
            UMSocketError err = UMSocketError_no_error;
            _directSocket = [_listener peelOffAssoc:_assocId error:&err];
            if(err != UMSocketError_no_error)
            {
                _directSocket = NULL;
            }
            [_registry registerIncomingLayer:self];
        }
        [_reconnectTimer stop];
        [self reportStatus];
    }
    else if(snp->sn_assoc_change.sac_state==SCTP_COMM_LOST)
    {
        _assocId = snp->sn_assoc_change.sac_assoc_id;
        _assocIdPresent=YES;
        [self.logFeed infoText:[NSString stringWithFormat:@" SCTP_ASSOC_CHANGE: SCTP_COMM_LOST->OFF (assocID=%ld)",(long)_assocId]];
        [self powerdownInReceiverThread];
        [self reportStatus];
#if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",_reconnectTimer.seconds]];
        }
#endif
        [_reconnectTimer start];
    }
    else if(snp->sn_assoc_change.sac_state==SCTP_CANT_STR_ASSOC)
    {
        [self.logFeed infoText:@" SCTP_ASSOC_CHANGE: SCTP_CANT_STR_ASSOC"];
        [self powerdownInReceiverThread];
        [self reportStatus];
#if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",_reconnectTimer.seconds]];
        }
#endif
        [_reconnectTimer start];
    }
    else if(snp->sn_assoc_change.sac_error!=0)
    {
        [self.logFeed majorError:snp->sn_assoc_change.sac_error withText:@" SCTP_ASSOC_CHANGE: SCTP_COMM_ERROR(%d)->OFF"];
        [self powerdownInReceiverThread];
        [self reportStatus];
#if defined(ULIBSCTP_CONFIG_DEBUG)
        if(self.logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",_reconnectTimer.seconds]];
        }
#endif
    }
}

-(void) handleLinkUpTcpEcnap
{
    [self.logFeed infoText:[NSString stringWithFormat:@" SCTP_TCP_ASSOC_CHANGE: SCTP_COMM_UP->IS"]];
    self.status=UMSOCKET_STATUS_IS;
    [_reconnectTimer stop];
    [self reportStatus];

}

-(void) handleLinkDownTcpEcnap
{
    _listener.firstMessage=YES;
    [self.logFeed infoText:[NSString stringWithFormat:@" SCTP_TCP_ASSOC_CHANGE: SCTP_COMM_LOST->OFF"]];
    self.status=UMSOCKET_STATUS_OFF;
    [self powerdownInReceiverThread];
    [self reportStatus];
    [_reconnectTimer start];
}

-(void) handlePeerAddrChange:(NSData *)event
                    streamId:(uint32_t)streamId
                  protocolId:(uint16_t)protocolId
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
               streamId:(uint32_t)streamId
             protocolId:(uint16_t)protocolId
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
        [self powerdownInReceiverThread];
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
    [self powerdownInReceiverThread];
    [self reportStatus];
    return -1;
}


-(int) handleShutdownEvent:(NSData *)event
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
        [self logDebug:@"SCTP_SHUTDOWN_EVENT"];
    }
#endif
    if(len < sizeof (struct sctp_shutdown_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_SHUTDOWN_EVENT"];
        [self powerdownInReceiverThread];
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
    [self powerdownInReceiverThread];
    [self reportStatus];
    return -1;
}


-(int) handleAdaptionIndication:(NSData *)event
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
        [self logDebug:@"SCTP_ADAPTATION_INDICATION"];
    }
#endif
    if(len < sizeof(struct sctp_adaptation_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_ADAPTATION_INDICATION"];
        [self powerdownInReceiverThread];
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
        [self powerdownInReceiverThread];
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
        [self logDebug:@"SCTP_AUTHENTICATION_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_authkey_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_AUTHENTICATION_EVENT"];
        [self powerdownInReceiverThread];
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
        [self logDebug:@"SCTP_STREAM_RESET_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_stream_reset_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_STREAM_RESET_EVENT"];
        [self powerdownInReceiverThread];
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
    
    self.status = UMSOCKET_STATUS_OFF;
    [self reportStatus];
    return UMSocketError_no_error;
}
#endif

-(int) handleSenderDryEvent:(NSData *)event
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
        [self logDebug:@"SCTP_SENDER_DRY_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_sender_dry_event))
    {
        [self.logFeed majorErrorText:@" Size Mismatch in SCTP_SENDER_DRY_EVENT"];
        [self powerdownInReceiverThread];
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
                          streamId:(uint32_t)streamId
                        protocolId:(uint16_t)protocolId
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
                            (unsigned int)streamId,
                            (unsigned int)protocolId,
                            data.hexString]];
        }
    #endif
        if(_defaultUser == NULL)
        {
            [self logDebug:@"RXT: USER instance not found. Maybe not bound yet?"];
            [self powerdownInReceiverThread];
            [self reportStatus];
            return UMSocketError_no_buffers;
        }

        /* if for whatever reason we have not realized we are in service yet, let us realize it now */
        if(self.status != UMSOCKET_STATUS_IS)
        {
    #if defined(ULIBSCTP_CONFIG_DEBUG)
            if(self.logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"force change status to IS"]];
            }
    #endif
            self.status = UMSOCKET_STATUS_IS;
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
                                  streamId:streamId
                                protocolId:protocolId
                                      data:data];
            }
            if([u.profile wantsMonitor])
            {
                [u.user sctpMonitorIndication:self
                                       userId:u.userId
                                     streamId:streamId
                                   protocolId:protocolId
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
        NSLog(@"configured_local_addresses=%@",configured_local_addresses);
        NSLog(@"configured_remote_addresses=%@",configured_remote_addresses);
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
        switch(_status)
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
                d[@"status"] = [NSString stringWithFormat:@"unknown(%d)",_status];
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
    return [UMSocket statusDescription:_status];
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
        if(_status != UMSOCKET_STATUS_IS)
        {
            uint32_t xassocId = -1;
            [_listener connectToAddresses:_configured_remote_addresses
                                     port:_configured_remote_port
                                    assoc:&xassocId
                                    layer:self];
            if(xassocId != -1)
            {
                _assocIdPresent = YES;
                _assocId = xassocId;
                [_registry registerAssoc:@(_assocId) forLayer:self];
            }
        }
    }
}

- (void)processError:(UMSocketError)err
{
    @autoreleasepool
    {
        /* FIXME */
        NSLog(@"processError %d %@ received in UMLayerSctp %@",err, [UMSocket getSocketErrorString:err], _layerName);
    }
}


- (void)processHangUp
{
    @autoreleasepool
    {
        NSLog(@"processHangUp received in UMLayerSctp %@",_layerName);
        [self powerdown];
        [self reportStatus];
    }
}

- (void)processInvalidSocket
{
    @autoreleasepool
    {
        NSLog(@"processInvalidSocket received in UMLayerSctp %@",_layerName);
        _isInvalid = YES;
        [self powerdown];
        [self reportStatus];
    }
}




- (ssize_t) sendEncapsulated:(NSData *)data
                      assoc:(uint32_t *)assocptr
                     stream:(uint16_t)streamId
                   protocol:(u_int32_t)protocolId
                      error:(UMSocketError *)err2
                       flags:(int)flags
{
    UMSocketError err = UMSocketError_no_error;
    if (*assocptr==-1)
    {
        if(err2)
        {
            *err2 = UMSocketError_not_connected;
        }
        return -1;
    }

    sctp_over_tcp_header header;
    memset(&header,0,sizeof(header));
    header.header_length = htonl(sizeof(header));
    header.payload_length = htonl(data.length);
    header.protocolId = htonl(protocolId);
    header.streamId = htons(streamId);
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

@end
