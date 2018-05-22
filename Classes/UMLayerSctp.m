//
//  UMLayerSctp.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

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
#import "UMLayerSctpReceiverThread.h"
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

#ifdef __APPLE__
#import <sctp/sctp.h>
#else
#include "netinet/sctp.h"
#endif


#import "UMLayerSctpUser.h"


@implementation UMLayerSctp

//@synthesize status;
@synthesize receiverThread;
@synthesize configured_local_addresses;
@synthesize configured_local_port;
@synthesize configured_remote_addresses;
@synthesize configured_remote_port;

@synthesize active_local_addresses;
@synthesize active_local_port;
@synthesize active_remote_addresses;
@synthesize active_remote_port;
@synthesize isPassive;
@synthesize defaultUser;

- (void)setLogLevel:(UMLogLevel )newLevel
{
    logLevel = newLevel;
    if(newLevel <= UMLOG_DEBUG)
    {
        NSLog(@"SCTP LogLevel is now DEBUG");
    }
}
- (UMLogLevel)logLevel
{
    return logLevel;
}

- (UMLayerSctp *)initWithTaskQueueMulti:(UMTaskQueueMulti *)tq
{
    return [self initWithTaskQueueMulti:tq name:@""];
}

- (UMLayerSctp *)initWithTaskQueueMulti:(UMTaskQueueMulti *)tq name:(NSString *)name
{
    self = [super initWithTaskQueueMulti:tq name:name];
    if(self)
    {
        _sctpSocket = NULL;
        timeoutInMs = 2400;
        _heartbeatSeconds = 30.0;
        _users = [[UMSynchronizedArray alloc]init];
        self.status = SCTP_STATUS_OFF;

        _inboundThroughputPackets   = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _inboundThroughputBytes     = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _outboundThroughputPackets  = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _outboundThroughputBytes    = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _reconnectTimerValue = 10.0;
        _reconnectTimer = [[UMTimer alloc]initWithTarget:self selector:@selector(reconnectTimerFires) object:NULL seconds:_reconnectTimerValue name:@"reconnect-timer" repeats:NO];
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
    UMLayerTask *task = [[UMSctpTask_Open alloc]initWithReceiver:self sender:caller];
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
    UMSctpTask_Data *task =
    [[UMSctpTask_Data alloc]initWithReceiver:self
                                      sender:caller
                                        data:sendingData
                                    streamId:sid
                                  protocolId:pid
                                  ackRequest:ack];
    [self queueFromUpper:task];
}

- (void)foosFor:(id<UMLayerSctpUserProtocol>)caller
{
    UMSctpTask_Manual_ForceOutOfService *task =
    [[UMSctpTask_Manual_ForceOutOfService alloc]initWithReceiver:self sender:caller];
    [self queueFromLowerWithPriority:task];
}

- (void)isFor:(id<UMLayerSctpUserProtocol>)caller
{
    UMSctpTask_Manual_InService *task =
    [[UMSctpTask_Manual_InService alloc]initWithReceiver:self sender:caller];
    [self queueFromLowerWithPriority:task];
}

#pragma mark -
#pragma mark Task Executors
/* LAYER API. The following methods are called by queued tasks */
- (void)_adminInitTask:(UMSctpTask_AdminInit *)task
{
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"adminInit"]];
    }
#endif
}

- (void)_adminSetConfigTask:(UMSctpTask_AdminSetConfig *)task
{
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"setConfig %@",task.config]];
    }
#endif
    [self setConfig:task.config applicationContext:task.appContext];
}

- (void)_adminAttachTask:(UMSctpTask_AdminAttach *)task
{
    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

    UMLayerSctpUser *u      = [[UMLayerSctpUser alloc]init];
    u.profile              = task.profile;
    u.user                  = user;
    u.userId                = task.userId;

    [_users addObject:u];
    if(defaultUser==NULL)
    {
        defaultUser = u;
    }

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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
    @try
    {
        if(self.status == SCTP_STATUS_M_FOOS)
        {
            @throw([NSException exceptionWithName:@"FOOS" reason:@"failed due to manual forced out of service status" userInfo:@{@"errno":@(EBUSY), @"backtrace": UMBacktrace(NULL,0)}]);
        }
        if(self.status == SCTP_STATUS_OOS)
        {
            @throw([NSException exceptionWithName:@"OOS" reason:@"status is OOS so SCTP is already establishing." userInfo:@{@"errno":@(EBUSY),@"backtrace": UMBacktrace(NULL,0)}]);
        }
        if(self.status == SCTP_STATUS_IS)
        {
            @throw([NSException exceptionWithName:@"IS" reason:@"status is IS so already up." userInfo:@{@"errno":@(EAGAIN),@"backtrace": UMBacktrace(NULL,0)}]);
        }
        if(_sctpSocket)
        {
#if (ULIBSCTP_CONFIG==Debug)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"old open socket detected. closing it first"];
            }
#endif
            [self powerdown];
        }
#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"socket()"]];
        }
#endif
        /**********************/
        /* SOCKET             */
        /**********************/
        _sctpSocket = [[UMSocketSCTP alloc]initWithType:UMSOCKET_TYPE_SCTP name:self.layerName];
        _sctpSocket.requestedRemoteAddresses = configured_remote_addresses;
        _sctpSocket.requestedRemotePort = configured_remote_port;
        _sctpSocket.requestedLocalAddresses = configured_local_addresses;
        _sctpSocket.requestedLocalPort = configured_local_port;

        if(_sctpSocket == NULL)
        {
            @throw([NSException exceptionWithName:@"SCTP_SOCKET_CREATION_FAILURE" reason:@"calling socket() for SCTP failed" userInfo:@{@"errno":@(errno),@"backtrace": UMBacktrace(NULL,0)}]);
        }
#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@"SCTP socket creation successful"];
        }
#endif


        /**********************/
        /* OPTIONS            */
        /**********************/
        
        [_sctpSocket switchToNonBlocking];
        
        UMSocketError err = [_sctpSocket setNoDelay];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not set NODELAY option on sctp %@: %d %@",self.layerName,err,[UMSocket getSocketErrorString:err]]];
        }

        err = [_sctpSocket setIPDualStack];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not disable IPV6_V6ONLY option on sctp %@ %d %@",self.layerName,err,[UMSocket getSocketErrorString:err]]];
        }

        err = [_sctpSocket setLinger];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not set SO_LINGER option on sctp %@ %d %@",self.layerName,err,[UMSocket getSocketErrorString:err]]];
        }
        err = [_sctpSocket setReuseAddr];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not set SO_REUSEADDR option on sctp %@ %d %@",self.layerName,err,[UMSocket getSocketErrorString:err]]];
        }
        err = [_sctpSocket setReusePort];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not set SCTP_REUSE_PORT option on sctp %@ %d %@",self.layerName,err,[UMSocket getSocketErrorString:err]]];
        }

        err = [_sctpSocket enableEvents];
        if(err!=UMSocketError_no_error)
        {
            [self logMinorError:[NSString stringWithFormat:@"can not enable sctp events on %@ %d %@",self.layerName,err,[UMSocket getSocketErrorString:err]]];
            return;
        }

        err = [_sctpSocket bind];
        if(err!=UMSocketError_no_error)
        {
            [self logMajorError:[NSString stringWithFormat:@"can not bind sctp connection %@ %d %@",self.layerName,err,[UMSocket getSocketErrorString:err]]];
            return;
        }

        _listener = [_registry listenerForPort:configured_local_port localIps:configured_local_addresses];
        [_listener startListening];
        _listenerStarted = YES;

        if(!self.isPassive)
        {
            /**********************/
            /* SCTP_CONNECTX      */
            /**********************/

            /* we are in async mode */
            err = [ _sctpSocket connectSCTP];
            [_registry registerLayer:self forAssoc:_sctpSocket.assocId];
        }
        [_registry startReceiver];
    }
    @catch (NSException *exception)
    {
#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"%@ %@",exception.name,exception.reason]];
        }
#endif
        if(exception.userInfo)
        {
            NSNumber *e = exception.userInfo[@"errno"];
            if(e)
            {
                [self logMajorError:e.intValue  location:@(__func__)];
            }
        }
        [self powerdown];
    }
    [self reportStatus];
}

- (void)_closeTask:(UMSctpTask_Close *)task
{
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <=UMLOG_DEBUG)
    {
        id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;
        [self logDebug:[NSString stringWithFormat:@"closing for %@",user.layerName]];
    }
#endif
    [self powerdown];
    [self reportStatus];
    if(_listenerStarted==YES)
    {
        [_listener stopListening];
    }
    _listener = NULL;
}


- (void)_dataTask:(UMSctpTask_Data *)task
{
    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"DATA: %@",task.data]];
        [self logDebug:[NSString stringWithFormat:@" streamId: %u",task.streamId]];
        [self logDebug:[NSString stringWithFormat:@" protocolId: %u",task.protocolId]];
        [self logDebug:[NSString stringWithFormat:@" ackRequest: %@",(task.ackRequest ? task.ackRequest.description  : @"(not present)")]];
    }
#endif

    @try
    {
        if(self.status == SCTP_STATUS_M_FOOS)
        {
            @throw([NSException exceptionWithName:@"FOOS" reason:@"Link out of service" userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
        }
        if(self.status != SCTP_STATUS_IS)
        {
            @throw([NSException exceptionWithName:@"NOT_IS" reason:@"trying to send data on non open link" userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
        }
        if(task.data == NULL)
        {
            @throw([NSException exceptionWithName:@"NULL" reason:@"trying to send NULL data" userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
        }
#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@" Calling sctp_sendmsg"];
        }
#endif
        UMSocketError err = UMSocketError_no_error;
        ssize_t sent_packets = [_sctpSocket sendSCTP:task.data
                                              stream:task.streamId
                                            protocol:task.protocolId
                                               error:&err];
        [_outboundThroughputBytes increaseBy:(uint32_t)task.data.length];
        [_outboundThroughputPackets increaseBy:(uint32_t)sent_packets];

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

#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@" sent_packets: %ld",sent_packets]];
        }
#endif
        if(sent_packets >= 0)
        {
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
            [self powerdown];
            [self reportStatus];
            switch(errno)
            {
                case 0:
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
                                                   reason:@"The socket is marked non-blocking and the requested operation would block."
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

                default:
                    @throw([NSException exceptionWithName:[NSString stringWithFormat:@"ERROR %d",errno]
                                                   reason:[NSString stringWithFormat:@"unknown error %d",errno]
                                                 userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                    break;
            }
            [self powerdown];
            [self reportStatus];
        }
    }
    @catch (NSException *exception)
    {
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
}


- (void)_foosTask:(UMSctpTask_Manual_ForceOutOfService *)task
{
    [self powerdown];
    self.status = SCTP_STATUS_M_FOOS;
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <=UMLOG_DEBUG)
    {
        [self logDebug:@"FOOS"];
    }
#endif
    [self reportStatus];
}

- (void)_isTask:(UMSctpTask_Manual_InService *)task
{
    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

    switch(self.status)
    {
        case SCTP_STATUS_M_FOOS:
#if (ULIBSCTP_CONFIG==Debug)
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual M-FOOS->IS requested"];
            }
#endif
            self.status = SCTP_STATUS_OFF;
            [self reportStatus];
            [self openFor:user];
            break;
        case SCTP_STATUS_OFF:
#if (ULIBSCTP_CONFIG==Debug)
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual OFF->IS requested"];
            }
#endif
            [self openFor:user];
            break;
        case SCTP_STATUS_OOS:
#if (ULIBSCTP_CONFIG==Debug)
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual OOS->IS requested"];
            }
#endif
            [self reportStatus];
            break;
        case SCTP_STATUS_IS:
#if (ULIBSCTP_CONFIG==Debug)
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual IS->IS requested"];
            }
#endif
            [self reportStatus];
            break;
    }
}


#pragma mark -
#pragma mark Helpers

- (void) powerdown
{
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
    }
#endif
    [receiverThread shutdownBackgroundTask];
    self.status = SCTP_STATUS_OOS;
    [_sctpSocket close];
    _sctpSocket = NULL;
    self.status = SCTP_STATUS_OFF;
    [_registry unregisterLayer:self];
}

- (void) powerdownInReceiverThread
{
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
    }
#endif
    self.status = SCTP_STATUS_OOS;
    [_sctpSocket close];
    _sctpSocket = NULL;
    self.status = SCTP_STATUS_OFF;
    [_registry unregisterLayer:self];
}


-(void) reportStatus
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

- (void)setNonBlocking
{
    [self logDebug:@"setting socket to non blocking"];
    [_sctpSocket switchToNonBlocking];
}

- (void)setBlocking
{
    [self logDebug:@"setting socket to blocking"];
    [_sctpSocket switchToBlocking];
}


- (void)receiveData /* returns number of packets processed */
{
    UMSocketSCTPReceivedPacket *rx = [_sctpSocket receiveSCTP];
    [self processReceivedData:rx];
}

- (void)processReceivedData:(UMSocketSCTPReceivedPacket *)rx
{
    if(rx.err==UMSocketError_try_again)
    {
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"receiveData: UMSocketError_try_again returned by receiveSCTP");
#endif
    }

    if(rx.err==UMSocketError_connection_reset)
    {
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"receiveData: UMSocketError_connection_reset returned by receiveSCTP");
#endif
        [self logDebug:@"ECONNRESET"];
        [self powerdownInReceiverThread];
        [self reportStatus];
    }
    if(rx.err==UMSocketError_connection_aborted)
    {
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"receiveData: UMSocketError_connection_aborted returned by receiveSCTP");
#endif
        [self logDebug:@"ECONNABORTED"];
        [self powerdownInReceiverThread];
        [self reportStatus];
    }
    if(rx.err==UMSocketError_connection_refused)
    {
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"receiveData: UMSocketError_connection_refused returned by receiveSCTP");
#endif
  /*      [self logDebug:@"ECONNREFUSED"];
        [self powerdownInReceiverThread];
        [self reportStatus];
   */
    }
    if(rx.err != UMSocketError_no_error)
    {
        [self logMinorError:[NSString stringWithFormat:@"receiveData: Error %d %@ returned by receiveSCTP",rx.err,[UMSocket getSocketErrorString:rx.err]]];
        [self powerdownInReceiverThread];
        [self reportStatus];
    }
    else
    {
        if(rx.isNotification)
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

- (void)processHangUp
{
}

- (void)processInvalidSocket
{
}

-(void) handleEvent:(NSData *)event
           streamId:(uint32_t)streamId
         protocolId:(uint16_t)protocolId
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
        case SCTP_AUTHENTICATION_EVENT:
            [self handleAuthenticationEvent:event streamId:streamId protocolId:protocolId];
            break;
        case SCTP_SENDER_DRY_EVENT:
            [self handleSenderDryEvent:event streamId:streamId protocolId:protocolId];
            break;

#if defined SCTP_STREAM_RESET_EVENT
        case  SCTP_STREAM_RESET_EVENT:
            [self handleStreamResetEvent:event streamId:streamId protocolId:protocolId];
            break;
#endif

        default:
            [logFeed majorErrorText:[NSString stringWithFormat:@"SCTP unknown event type: %hu", snp->sn_header.sn_type]];
            [logFeed majorErrorText:[NSString stringWithFormat:@" RX-STREAM: %d",streamId]];
            [logFeed majorErrorText:[NSString stringWithFormat:@" RX-PROTO: %d", protocolId]];
            [logFeed majorErrorText:[NSString stringWithFormat:@" RX-DATA: %@",event.description]];
    }
}


-(void) handleAssocChange:(NSData *)event
                 streamId:(uint32_t)streamId
               protocolId:(uint16_t)protocolId
{
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_ASSOC_CHANGE"];
    }
#endif
    if(len < sizeof (struct sctp_assoc_change))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_ASSOC_CHANGE"];
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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
        [logFeed infoText:@" SCTP_ASSOC_CHANGE: SCTP_COMM_UP->IS"];
        self.status=SCTP_STATUS_IS;
        [self reportStatus];
    }
    else if(snp->sn_assoc_change.sac_state==SCTP_COMM_LOST)
    {
        [logFeed infoText:@" SCTP_ASSOC_CHANGE: SCTP_COMM_LOST->OFF"];
        self.status=SCTP_STATUS_OFF;
        [self reportStatus];
        [self powerdownInReceiverThread];
#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",(_reconnectTimer.duration / 1000000.0)]];
        }
#endif

        [_reconnectTimer start];
    }
    else if(snp->sn_assoc_change.sac_state==SCTP_CANT_STR_ASSOC)
    {
        [logFeed infoText:@" SCTP_ASSOC_CHANGE: SCTP_CANT_STR_ASSOC->OFF"];
        self.status=SCTP_STATUS_OFF;
        [self reportStatus];
        [self powerdownInReceiverThread];
#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",(_reconnectTimer.duration / 1000000.0)]];
        }
#endif
        [_reconnectTimer start];

    }
    else if(snp->sn_assoc_change.sac_error!=0)
    {
        [logFeed majorError:snp->sn_assoc_change.sac_error withText:@" SCTP_ASSOC_CHANGE: SCTP_COMM_ERROR(%d)->OFF"];
        self.status=SCTP_STATUS_OFF;
        [self powerdownInReceiverThread];
#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"starting reconnectTimer %8.3lfs",(_reconnectTimer.duration / 1000000.0)]];
        }
#endif

    }
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

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_PEER_ADDR_CHANGE"];
    }
#endif
    if(len < sizeof (struct sctp_paddr_change))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_PEER_ADDR_CHANGE"];
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"  spc_aaddr: ipv4:%s", ap]];
        }
    }
    else
    {
        sin6 = (struct sockaddr_in6 *)&snp->sn_paddr_change.spc_aaddr;
        ap = inet_ntop(AF_INET6, &sin6->sin6_addr, addrbuf, INET6_ADDRSTRLEN);
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"  spc_aaddr: ipv6:%s", ap]];
        }
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_REMOTE_ERROR"];
    }
#endif
    if(len < sizeof (struct sctp_remote_error))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_REMOTE_ERROR"];
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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


#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_SEND_FAILED"];
    }
#endif
    if(len < sizeof (struct sctp_send_failed))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_SEND_FAILED"];
        [self powerdownInReceiverThread];
        return UMSocketError_not_supported_operation;
    }
    [logFeed majorErrorText:@"SCTP_SEND_FAILED"];
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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
    [logFeed majorErrorText:[NSString stringWithFormat:@"SCTP sendfailed: len=%du err=%d\n", snp->sn_send_failed.ssf_length,snp->sn_send_failed.ssf_error]];
    [self powerdownInReceiverThread];
    return -1;
}


-(int) handleShutdownEvent:(NSData *)event
                  streamId:(uint32_t)streamId
                protocolId:(uint16_t)protocolId
{
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_SHUTDOWN_EVENT"];
    }
#endif
    if(len < sizeof (struct sctp_shutdown_event))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_SHUTDOWN_EVENT"];
        [self powerdownInReceiverThread];
        return UMSocketError_not_supported_operation;
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  sse_type: %d",     (int)snp->sn_shutdown_event.sse_type]];
        [self logDebug:[NSString stringWithFormat:@"  sse_flags: %d",    (int)snp->sn_shutdown_event.sse_flags]];
        [self logDebug:[NSString stringWithFormat:@"  sse_length: %d",   (int)snp->sn_shutdown_event.sse_length]];
        [self logDebug:[NSString stringWithFormat:@"  sse_assoc_id: %d", (int)snp->sn_shutdown_event.sse_assoc_id]];
    }
#endif
    [logFeed warningText:@"SCTP_SHUTDOWN_EVENT->POWERDOWN"];
    [self powerdownInReceiverThread];
    return -1;
}


-(int) handleAdaptionIndication:(NSData *)event
                       streamId:(uint32_t)streamId
                     protocolId:(uint16_t)protocolId
{
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_ADAPTATION_INDICATION"];
    }
#endif
    if(len < sizeof(struct sctp_adaptation_event))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_ADAPTATION_INDICATION"];
        [self powerdownInReceiverThread];
        return UMSocketError_not_supported_operation;
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_PARTIAL_DELIVERY_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_pdapi_event))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_PARTIAL_DELIVERY_EVENT"];
        [self powerdownInReceiverThread];
        return UMSocketError_not_supported_operation;
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_AUTHENTICATION_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_authkey_event))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_AUTHENTICATION_EVENT"];
        [self powerdownInReceiverThread];
        return UMSocketError_not_supported_operation;
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
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
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_STREAM_RESET_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_stream_reset_event))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_STREAM_RESET_EVENT"];
        [self powerdownInReceiverThread];
        return UMSocketError_not_supported_operation;
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  strreset_type: %d",     (int)snp->sn_strreset_event.strreset_type]];
        [self logDebug:[NSString stringWithFormat:@"  strreset_flags: %d",    (int)snp->sn_strreset_event.strreset_flags]];
        [self logDebug:[NSString stringWithFormat:@"  strreset_length: %d",   (int)snp->sn_strreset_event.strreset_length]];
        [self logDebug:[NSString stringWithFormat:@"  strreset_assoc_id: %d", (int)snp->sn_strreset_event.strreset_assoc_id]];
    }
#endif
    return UMSocketError_no_error;
}
#endif

-(int) handleSenderDryEvent:(NSData *)event
                   streamId:(uint32_t)streamId
                 protocolId:(uint16_t)protocolId
{
    const union sctp_notification *snp;
    snp = event.bytes;
    NSUInteger len = event.length;

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"SCTP_SENDER_DRY_EVENT"];
    }
#endif
    if(len < sizeof(struct sctp_sender_dry_event))
    {
        [logFeed majorErrorText:@" Size Mismatch in SCTP_SENDER_DRY_EVENT"];
        [self powerdownInReceiverThread];
        return UMSocketError_not_supported_operation;
    }
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"  sender_dry_type: %d",     (int)snp->sn_sender_dry_event.sender_dry_type]];
        [self logDebug:[NSString stringWithFormat:@"  sender_dry_flags: %d",    (int)snp->sn_sender_dry_event.sender_dry_flags]];
        [self logDebug:[NSString stringWithFormat:@"  sender_dry_length: %d",   (int)snp->sn_sender_dry_event.sender_dry_length]];
        [self logDebug:[NSString stringWithFormat:@"  sender_dry_assoc_id: %d", (int)snp->sn_sender_dry_event.sender_dry_assoc_id]];
    }
#endif
    return UMSocketError_no_error;
}


- (UMSocketError) dataIsAvailableSCTP:(int *)hasData
                               hangup:(int *)hasHup
{
    return [_sctpSocket dataIsAvailableSCTP:timeoutInMs
                                  dataAvail:hasData
                                     hangup:hasHup];
}

- (UMSocketError) sctpReceivedData:(NSData *)data
                          streamId:(uint32_t)streamId
                        protocolId:(uint16_t)protocolId
{
    [_inboundThroughputBytes increaseBy:(int)data.length];
    [_inboundThroughputPackets increaseBy:1];

#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"RXT: got %u bytes on stream %u protocol_id: %u",
                        (unsigned int)data.length,
                        (unsigned int)streamId,
                        (unsigned int)protocolId]];
    }
#endif
    if(defaultUser == NULL)
    {
        [self logDebug:@"RXT: USER instance not found. Maybe not bound yet?"];
        [self powerdownInReceiverThread];
        return UMSocketError_no_buffers;
    }

    /* if for whatever reason we have not realized we are in service yet, let us realize it now */
    if(self.status != SCTP_STATUS_IS)
    {
#if (ULIBSCTP_CONFIG==Debug)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"force change status to IS"]];
        }
#endif
        self.status = SCTP_STATUS_IS;
        [self reportStatus];
    }

    NSArray *usrs = [_users arrayCopy];
    for(UMLayerSctpUser *u in usrs)
    {
        if( [u.profile wantsProtocolId:protocolId]
           || [u.profile wantsStreamId:streamId])
        {
#if (ULIBSCTP_CONFIG==Debug)
            if(logLevel <= UMLOG_DEBUG)
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
#pragma mark -
#pragma mark Config Handling
- (void)setConfig:(NSDictionary *)cfg applicationContext:(id<UMLayerSctpApplicationContextProtocol>)appContext
{
    [self readLayerConfig:cfg];
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
        configured_local_port = [cfg[@"local-port"] intValue];
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
        configured_remote_port = [cfg[@"remote-port"] intValue];
    }
    if (cfg[@"passive"])
    {
        isPassive = [cfg[@"passive"] boolValue];
    }
    if (cfg[@"heartbeat"])
    {
        _heartbeatSeconds = [cfg[@"heartbeat"] doubleValue];
    }
    if (cfg[@"reconnect-timer"])
    {
        _reconnectTimerValue = [cfg[@"reconnect-timer"] doubleValue];
        _reconnectTimer.duration = (UMMicroSec) (_reconnectTimerValue * 1000000.0);
    }
#ifdef ULIB_SCTP_DEBUG
    NSLog(@"configured_local_addresses=%@",configured_local_addresses);
    NSLog(@"configured_remote_addresses=%@",configured_remote_addresses);
#endif
}


- (NSDictionary *)config
{
    NSMutableDictionary *config = [[NSMutableDictionary alloc]init];
    [self addLayerConfig:config];
    config[@"local-ip"] = [configured_local_addresses componentsJoinedByString:@" "];
    config[@"local-port"] = @(configured_local_port);
    config[@"remote-ip"] = [configured_remote_addresses componentsJoinedByString:@" "];
    config[@"remote-port"] = @(configured_remote_port);
    config[@"passive"] = isPassive ? @YES : @ NO;
    config[@"heartbeat"] = @(_heartbeatSeconds);
    config[@"reconnect-timer"] = @(_reconnectTimerValue);
    config[@"heartbeat"] = @(_heartbeatSeconds);

    return config;
}

- (NSDictionary *)apiStatus
{
    NSMutableDictionary *d = [[NSMutableDictionary alloc]init];
    switch(_status)
    {
        case SCTP_STATUS_M_FOOS:
            d[@"status"] = @"M-FOOS";
            break;
        case SCTP_STATUS_OFF:
            d[@"status"] = @"OFF";
            break;
        case SCTP_STATUS_OOS:
            d[@"status"] = @"OOS";
            break;
        case SCTP_STATUS_IS:
            d[@"status"] = @"IS";
            break;
        default:
            d[@"status"] = [NSString stringWithFormat:@"unknown(%d)",_status];
            break;
    }
    d[@"name"] = self.layerName;
    
    d[@"configured-local-port"] = @(configured_local_port);
    d[@"configured-remote-port"] = @(configured_remote_port);
    d[@"active-local-port"] = @(active_local_port);
    d[@"active-remote-port"] = @(active_remote_port);

    if(configured_local_addresses.count > 0)
    {
        d[@"configured-local-addresses"] = [configured_local_addresses copy];
    }
    if(configured_remote_addresses.count>0)
    {
        d[@"configured-remote-addresses"] = [configured_remote_addresses copy];
    }
    if(active_local_addresses.count)
    {
        d[@"active-local-addresses"] = [active_local_addresses copy];
    }
    if(active_remote_addresses.count)
    {
        d[@"active-remote-addresses"] = [active_remote_addresses copy];
    }
    d[@"is-passive"] = isPassive ? @(YES) : @(NO);
    d[@"poll-timeout-in-ms"] = @(timeoutInMs);
    d[@"heartbeat"] = @(_heartbeatSeconds);
    return d;
}

- (void)stopDetachAndDestroy
{
    /* FIXME: do something here */
}

- (NSString *)statusString
{
    switch(_status)
    {
        case    SCTP_STATUS_M_FOOS:
            return @"M-FOOS";
        case  SCTP_STATUS_OFF:
            return @"OFF";
        case SCTP_STATUS_OOS:
            return @"OOS";
        case SCTP_STATUS_IS:
            return @"IS";
    }
    return @"UNDEFINED";
}

-(void)dealloc
{
    if(_listenerStarted==YES)
    {
        [_listener stopListening];
    }
    _listener = NULL;
}

- (void)reconnectTimerFires
{
#if (ULIBSCTP_CONFIG==Debug)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:@"reconnectTimerFires"];
    }
#endif
    [_reconnectTimer stop];
    [ _sctpSocket connectSCTP];
    [_registry registerLayer:self forAssoc:_sctpSocket.assocId];
}


@end
