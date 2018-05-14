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
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/poll.h>
#ifdef __APPLE__
#import <sctp/sctp.h>
#else
#include "netinet/sctp.h"
#endif

#include <arpa/inet.h>

//#define ULIB_SCCTP_CAN_DEBUG 1


#ifdef __APPLE__
#include <sys/utsname.h>

#define MSG_NOTIFICATION_MAVERICKS 0x40000        /* notification message */
#define MSG_NOTIFICATION_YOSEMITE  0x80000        /* notification message */

#endif
#import "UMLayerSctpUser.h"

@implementation UMLayerSctp

//@synthesize status;
@synthesize receiverThread;
@synthesize fd;
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
@synthesize heartbeatMs;

//-(int) handleEvent:(NSData *)event sinfo:(struct sctp_sndrcvinfo *)sinfo;

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
        fd = -1;
        timeoutInMs = 400;
        heartbeatMs = 30000;
        _users = [[UMSynchronizedArray alloc]init];
        self.status = SCTP_STATUS_OFF;

        _inboundThroughputPackets   = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _inboundThroughputBytes     = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _outboundThroughputPackets  = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];
        _outboundThroughputBytes    = [[UMThroughputCounter alloc]initWithResolutionInSeconds: 1.0 maxDuration: 1260.0];

#ifdef __APPLE__
        int major;
        int minor;
        int sub;
        
        struct utsname ut;
        uname(&ut);
        sscanf(ut.release,"%d.%d.%d",&major,&minor,&sub);
        if(major >= 14)
        {
            msg_notification_mask = MSG_NOTIFICATION_YOSEMITE;
        }
        else
        {
            msg_notification_mask = MSG_NOTIFICATION_MAVERICKS;
        }
#else
        msg_notification_mask = MSG_NOTIFICATION;
#endif

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
#if defined(ULIB_SCCTP_CAN_DEBUG)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"adminInit"]];
    }
#endif
}

- (void)_adminSetConfigTask:(UMSctpTask_AdminSetConfig *)task
{
#if defined(ULIB_SCCTP_CAN_DEBUG)
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

#if defined(ULIB_SCCTP_CAN_DEBUG)
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
    int err;
    struct sctp_event_subscribe event;
    int i;
    int usable_ips;
    
    const int on = 1;
    
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
        if(self.fd >= 0)
        {
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"old open socket detected. closing it first"];
            }
#endif
            [self powerdown];
        }
#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"socket()"]];
        }
#endif
        /**********************/
        /* SOCKET             */
        /**********************/
#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@"calling socket(AF_INET, SOCK_STREAM, IPPROTO_SCTP)"];
        }
#endif
        self.fd = socket(AF_INET, SOCK_STREAM, IPPROTO_SCTP);
#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@" socket(AF_INET, SOCK_STREAM, IPPROTO_SCTP) returned fd=%d errno=%d",self.fd,errno]];
        }
#endif
        if(self.fd < 0)
        {
            @throw([NSException exceptionWithName:@"socket(AF_INET, SOCK_STREAM, IPPROTO_SCTP)" reason:@"calling socket failed" userInfo:@{@"errno":@(errno),@"backtrace": UMBacktrace(NULL,0)}]);
        }
#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@"socket() successful"];
        }
#endif
        /**********************/
        /* OPTIONS            */
        /**********************/
        
        [self setNonBlocking];
        
        setsockopt(self.fd, IPPROTO_SCTP, SCTP_NODELAY, (char *)&on, sizeof(on));
#ifdef	__APPLE__
        setsockopt(self.fd, IPPROTO_SCTP, SCTP_REUSE_PORT, (char *)&on, sizeof(on));
#endif


#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@"enabling linger using setsockopt(self.fd, SOL_SOCKET, SO_LINGER, &linger, sizeof (struct linger));"];
        }
#endif
        struct linger linger;
        linger.l_onoff  = 1;
        linger.l_linger = 32;
        setsockopt(self.fd, SOL_SOCKET, SO_LINGER, &linger, sizeof (struct linger));


        /* FIXME: we should not bind/bindx if we use CONNECTX  with a nailed down destination port otherwise a incoming port becomes unique to one connection */
        /**********************/
        /* BIND               */
        /**********************/
        //if(self.isPassive)
        //{
            usable_ips = -1;
            NSMutableArray *usable_addresses = [[NSMutableArray alloc]init];
            for(NSString *address in self.configured_local_addresses)
            {
                struct sockaddr_in        local_addr;
                memset(&local_addr,0x00,sizeof(local_addr));
                
                local_addr.sin_family = AF_INET;
#ifdef __APPLE__
                local_addr.sin_len         = sizeof(struct sockaddr_in);
#endif
                
                inet_aton(address.UTF8String, &local_addr.sin_addr);
                local_addr.sin_port = htons(self.configured_local_port);
                
                if(usable_ips == -1)
                {
                    /* FIRST IP */
#if defined(ULIB_SCCTP_CAN_DEBUG)
                    if(logLevel <= UMLOG_DEBUG)
                    {
                        [self logDebug:[NSString stringWithFormat:@"bind(%@:%d)",address,self.configured_local_port]];
                    }
#endif
                    err = bind(self.fd, (struct sockaddr *)&local_addr,sizeof(local_addr));
#if defined(ULIB_SCCTP_CAN_DEBUG)
                    if(logLevel <= UMLOG_DEBUG)
                    {
                        [self logDebug:[NSString stringWithFormat:@"bind(%@:%d) returns %d (errno=%d)",address,self.configured_local_port,err,errno]];
                    }
#endif
                    if(err!=0)
                    {
                        [self logMinorError:errno location:@"bind"];
                    }
                    else
                    {
                        usable_ips = 1;
                        [usable_addresses addObject:address];
                    }
                }
                else
                {
                    /* Further IP */
#if defined(ULIB_SCCTP_CAN_DEBUG)
                    if(logLevel <= UMLOG_DEBUG)
                    {
                        [self logDebug:[NSString stringWithFormat:@"sctp_bindx(%@:%d)",address,configured_local_port]];
                    }
#endif
                    err = sctp_bindx(self.fd, (struct sockaddr *)&local_addr,1,SCTP_BINDX_ADD_ADDR);
#if defined(ULIB_SCCTP_CAN_DEBUG)
                    if(logLevel <= UMLOG_DEBUG)
                    {
                        [self logDebug:[NSString stringWithFormat:@"sctp_bindx(%@) returns %d (errno=%d)",address,err,errno]];
                    }
#endif
                    if(err!=0)
                    {
                        [self logMinorError:errno location:@"bind"];
                    }
                    else
                    {
                        usable_ips++;
                        [usable_addresses addObject:address];
                    }
                }
            }
            if(usable_ips <= 0)
            {
                @throw([NSException exceptionWithName:@"EADDRNOTAVAIL" reason:@"no configured IP is available" userInfo:@{@"errno":@(EADDRNOTAVAIL),@"backtrace": UMBacktrace(NULL,0)}]);
            }
        //}
        /**********************/
        /* ENABLING EVENTS    */
        /**********************/

        self.status = SCTP_STATUS_OOS;
        
        bzero((void *)&event, sizeof(struct sctp_event_subscribe));
        event.sctp_data_io_event			= 1;
        event.sctp_association_event		= 1;
        event.sctp_address_event			= 1;
        event.sctp_send_failure_event		= 1;
        event.sctp_peer_error_event			= 1;
        event.sctp_shutdown_event			= 1;
        event.sctp_partial_delivery_event	= 1;
        event.sctp_adaptation_layer_event	= 1;
        event.sctp_authentication_event		= 1;
#ifndef LINUX
        event.sctp_stream_reset_events		= 1;
#endif

#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"setsockopt() enabling events"]];
        }
#endif
        if (setsockopt(self.fd, IPPROTO_SCTP, SCTP_EVENTS, &event, sizeof(event)) != 0)
        {
            @throw([NSException exceptionWithName:@"EVENTS" reason:@"setsockoption failed to enable events" userInfo:@{@"errno":@(errno),@"backtrace": UMBacktrace(NULL,0)}]);
        }
        
        if(self.isPassive)
        {
            /**********************/
            /* LISTEN             */
            /**********************/
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"listen()"]];
            }
#endif
            err =  listen(self.fd, 10);
            if(err !=0)
            {
                [self logMinorError:errno location:@"listen"];
            }
            
            /* accorindg to the draft, there is no need to call accept (if we call connect) */
            struct sockaddr saddr;
            socklen_t		saddr_len;
            
            saddr_len = sizeof(saddr);
            memset(&saddr,0x00,saddr_len);
            
            /* we need to block on this accept call */
            [self setBlocking];
            
            int newsock = accept(self.fd, &saddr, &saddr_len);
            [self setNonBlocking];
            if (newsock<0)
            {
                [self logMajorError:errno location:@"accept"];
            }
            else
            {
                if(self.fd >=0)
                {
                    close(self.fd);
                }
                self.fd = newsock;
                [self setNonBlocking];
            }
        }
        else /* not passive */
        {
            /**********************/
            /* CONNECTX           */
            /**********************/
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"connectx()"]];
            }
#endif
            int remote_addresses_count = (int)self.configured_remote_addresses.count;
            struct sockaddr_in *remote_addresses = malloc(sizeof(struct sockaddr_in) * remote_addresses_count);
            sctp_assoc_t assoc;
            memset(&assoc,0x00,sizeof(assoc));
            
            memset(remote_addresses,0x00,sizeof(struct sockaddr_in) * remote_addresses_count);
            for(i=0;i<remote_addresses_count;i++)
            {
                remote_addresses[i].sin_family = AF_INET;
#ifdef __APPLE__
                remote_addresses[i].sin_len = sizeof(struct sockaddr_in);
#endif
                NSString *address = [self.configured_remote_addresses objectAtIndex:i];
                inet_aton(address.UTF8String, &remote_addresses[i].sin_addr);
                remote_addresses[i].sin_port = htons(self.configured_remote_port);
            }
            err =  sctp_connectx(self.fd,(struct sockaddr *)&remote_addresses[0],remote_addresses_count,&assoc);
            free(remote_addresses);
            remote_addresses = NULL;
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                if(errno == EINPROGRESS)
                {
                    [self logDebug:[NSString stringWithFormat:@"connectx() returned %d (errno=EINPROGRESS)",err]];
                }
                else
                {
                    [self logDebug:[NSString stringWithFormat:@"connectx() returned %d (errno=%d)",err,errno]];
                }
            }
#endif
            if ((err < 0) && (err !=EINPROGRESS))
            {
                if(errno != EINPROGRESS)
                {
                    @throw([NSException exceptionWithName:@"CONNECTX" reason:@"sctp_connectx returns error" userInfo:@{@"errno":@(errno),@"backtrace": UMBacktrace(NULL,0)}]);
                }
            }
        }
        if(self.fd>=0)
        {
            self.receiverThread = [[UMLayerSctpReceiverThread alloc]initWithSctpLink:self];
            self.receiverThread.name =[NSString stringWithFormat:@"%@.sctpReceiverTread",layerName];
            [self.receiverThread startBackgroundTask];
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"started receiver thread"]];
            }
#endif
            self.status = SCTP_STATUS_OOS; /* we are CONNECTING but not yet CONNECTED. We are once the SCTP event up is received */
        }
    }
    @catch (NSException *exception)
    {
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
#if defined(ULIB_SCCTP_CAN_DEBUG)
    if(logLevel <=UMLOG_DEBUG)
    {
        id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;
        [self logDebug:[NSString stringWithFormat:@"closing for %@",user.layerName]];
    }
#endif
    [self powerdown];
    [self reportStatus];
}


- (void)_dataTask:(UMSctpTask_Data *)task
{
    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

#if defined(ULIB_SCCTP_CAN_DEBUG)
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
#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@" Calling sctp_sendmsg"];
        }
#endif
        ssize_t sent_packets = sctp_sendmsg(
                                            fd,                                 /* file descriptor */
                                            (const void *)task.data.bytes,      /* data pointer */
                                            (size_t) task.data.length,          /* data length */
                                            NULL,                               /* const struct sockaddr *to */
                                            0,                                  /* socklen_t tolen */
                                            (u_int32_t)	htonl(task.protocolId), /* protocol Id */
                                            (u_int32_t)	0,                      /* uint32_t flags */
                                            task.streamId, //htons(streamId),	/* uint16_t stream_no */
                                            0,                                  /* uint32_t timetolive, */
                                            0);                                 /*	 uint32_t context */

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

#if defined(ULIB_SCCTP_CAN_DEBUG)
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
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual OFF->IS requested"];
            }
#endif
            [self openFor:user];
            break;
        case SCTP_STATUS_OOS:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual OOS->IS requested"];
            }
#endif
            [self reportStatus];
            break;
        case SCTP_STATUS_IS:
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
#if defined(ULIB_SCCTP_CAN_DEBUG)
    if(logLevel <= UMLOG_DEBUG)
    {
        [logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
    }
#endif
    [receiverThread shutdownBackgroundTask];
    self.status = SCTP_STATUS_OOS;
    if(fd >=0)
    {
        close(fd);
        fd = -1;
    }
    self.status = SCTP_STATUS_OFF;
}

- (void) powerdownInReceiverThread
{
#if defined(ULIB_SCCTP_CAN_DEBUG)
    if(logLevel <= UMLOG_DEBUG)
    {
        [logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
    }
#endif
    self.status = SCTP_STATUS_OOS;
    if(fd >=0)
    {
        close(fd);
        fd = -1;
    }
    self.status = SCTP_STATUS_OFF;
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
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags  | O_NONBLOCK);
}

- (void)setBlocking
{
    [self logDebug:@"setting socket to blocking"];
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags  & ~O_NONBLOCK);
}

#define SCTP_RXBUF 10240

- (int)receiveData /* returns number of packets processed */
{
    char					buffer[SCTP_RXBUF+1];
    int						flags;
    struct sockaddr			source_address;
    struct sctp_sndrcvinfo	sinfo;
    socklen_t				fromlen;
    ssize_t					bytes_read = 0;
    
    flags = 0;
    fromlen = sizeof(source_address);
    memset(&source_address,0,sizeof(source_address));
    memset(&sinfo,0,sizeof(sinfo));
    memset(&buffer[0],0xFA,sizeof(buffer));

    //	[self logDebug:[NSString stringWithFormat:@"RXT: calling sctp_recvmsg(fd=%d)",link->fd);
    //	debug("sctp",0,"RXT: calling sctp_recvmsg. link=%08lX",(unsigned long)link);
    bytes_read = sctp_recvmsg (fd, buffer, SCTP_RXBUF, &source_address,&fromlen,&sinfo,&flags);
    //	debug("sctp",0,"RXT: returned from sctp_recvmsg. link=%08lX",(unsigned long)link);
    //	[self logDebug:[NSString stringWithFormat:@"RXT: sctp_recvmsg: bytes read =%ld, errno=%d",(long)bytes_read,(int)errno);
    if(bytes_read == 0)
    {
        if(errno==ECONNRESET)
        {
            [self powerdown];
            [self reportStatus];
            return 0;
        }
    }
    if(bytes_read <= 0)
    {
        /* we are having a non blocking read here */
        
        if(errno==EAGAIN)
        {
            return 0;
        }
        
        [self logMajorError:errno  location:@"sctp_recvmsg"];
        if(errno==ECONNRESET)
        {
            [self logDebug:@"ECONNRESET"];
            [self powerdownInReceiverThread];
            return -1;
        }
        else if(errno==ECONNABORTED)
        {
            [self logDebug:@"ECONNABORTED"];
            [self powerdownInReceiverThread];
            return -1;
        }
        else if(errno==ECONNREFUSED)
        {
            [self logDebug:@"ECONNREFUSED"];
            [self powerdownInReceiverThread];
            return -1;
        }
        else
        {
            [self powerdownInReceiverThread];
            return -1;
        }
    }

#if defined(ULIB_SCCTP_CAN_DEBUG)
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"FLAGS: 0x%08x",flags]];
    }
#endif
    NSData *data = [NSData dataWithBytes:&buffer length:bytes_read];
    [_inboundThroughputBytes increaseBy:(uint32_t)bytes_read];
    [_inboundThroughputPackets increaseBy:1];

    if(flags & msg_notification_mask)
    {
#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"RXT: got SCTP Notification of %u bytes", (unsigned int)bytes_read]];
        }
#endif
        return [self handleEvent:data sinfo:&sinfo];
    }
    else
    {
#if defined(ULIB_SCCTP_CAN_DEBUG)
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"RXT: got %u bytes on stream %hu protocol_id: %d",
                            (unsigned int)bytes_read,
                            sinfo.sinfo_stream,
                            ntohl(sinfo.sinfo_ppid)]];
        }
#endif

        if(defaultUser == NULL)
        {
            [self logDebug:@"RXT: USER instance not found. Maybe not bound yet?"];
            [self powerdownInReceiverThread];
            return -1;
        }
        /* if for whatever reason we have not realized we are in service yet, let us realize it now */
        if(self.status != SCTP_STATUS_IS)
        {
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"force change status to IS"]];
            }
#endif
            self.status = SCTP_STATUS_IS;
            [self reportStatus];
        }
        
        uint16_t streamId = sinfo.sinfo_stream;
        uint32_t protocolId = ntohl(sinfo.sinfo_ppid);

        NSArray *usrs = [_users arrayCopy];
        for(UMLayerSctpUser *u in usrs)
        {
            if( [u.profile wantsProtocolId:protocolId]
               || [u.profile wantsStreamId:streamId])
            {
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
    }
    return 1;
}

-(int) handleEvent:(NSData *)event sinfo:(struct sctp_sndrcvinfo *)sinfo /* return 1 for processed data, 0 for no data, -1 for terminate */
{
    
    const union sctp_notification *snp;
    
    char addrbuf[INET6_ADDRSTRLEN];
    const char *ap;
    struct sockaddr_in *sin;
    struct sockaddr_in6 *sin6;
    
    snp = event.bytes;
    NSUInteger len = event.length;
    
    switch(snp->sn_header.sn_type)
    {
        case SCTP_ASSOC_CHANGE:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_ASSOC_CHANGE"];
            }
#endif
            if(len < sizeof (struct sctp_assoc_change))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_ASSOC_CHANGE"];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  sac_type: %d",             (int)snp->sn_assoc_change.sac_type]];
                [self logDebug:[NSString stringWithFormat:@"  sac_flags: %d",            (int)snp->sn_assoc_change.sac_flags]];
                [self logDebug:[NSString stringWithFormat:@"  sac_length: %d",           (int)snp->sn_assoc_change.sac_length]];
                [self logDebug:[NSString stringWithFormat:@"  sac_state: %d",            (int)snp->sn_assoc_change.sac_state]];
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
                return 0;
            }
            else if(snp->sn_assoc_change.sac_state==SCTP_COMM_LOST)
            {
                [logFeed infoText:@" SCTP_ASSOC_CHANGE: SCTP_COMM_LOST->OFF"];
                self.status=SCTP_STATUS_OFF;
                [self reportStatus];
                [self powerdownInReceiverThread];
                return -1;
            }
            else if (snp->sn_assoc_change.sac_state == SCTP_CANT_STR_ASSOC)
            {
                [logFeed infoText:@" SCTP_CANT_STR_ASSOC: SCTP_COMM_LOST->OFF"];
                self.status=SCTP_STATUS_OFF;
                [self reportStatus];
                [self powerdownInReceiverThread];
                return -1;
            }
            else if(snp->sn_assoc_change.sac_error!=0)
            {
                [logFeed majorError:snp->sn_assoc_change.sac_error withText:@" SCTP_ASSOC_CHANGE: SCTP_COMM_ERROR(%d)->OFF"];
                self.status=SCTP_STATUS_OFF;
                [self powerdownInReceiverThread];
                return -1;
            }
            break;
            
        case SCTP_PEER_ADDR_CHANGE:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_PEER_ADDR_CHANGE"];
            }
#endif
            if(len < sizeof (struct sctp_paddr_change))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_PEER_ADDR_CHANGE"];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
            break;
            
        case SCTP_REMOTE_ERROR:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_REMOTE_ERROR"];
            }
#endif
            if(len < sizeof (struct sctp_remote_error))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_REMOTE_ERROR"];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
            break;
        case SCTP_SEND_FAILED:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_SEND_FAILED"];
            }
#endif
            if(len < sizeof (struct sctp_send_failed))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_SEND_FAILED"];
                [self powerdownInReceiverThread];
                return -1;
            }
            [logFeed majorErrorText:@"SCTP_SEND_FAILED"];
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
            break;
        case SCTP_SHUTDOWN_EVENT:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_SHUTDOWN_EVENT"];
            }
#endif
            if(len < sizeof (struct sctp_shutdown_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_SHUTDOWN_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
            break;
#ifdef	SCTP_ADAPTATION_INDICATION
        case SCTP_ADAPTATION_INDICATION:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_ADAPTATION_INDICATION"];
            }
#endif
            if(len < sizeof(struct sctp_adaptation_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_ADAPTATION_INDICATION"];
                [self powerdownInReceiverThread];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  sai_type: %d",           (int)snp->sn_adaptation_event.sai_type]];
                [self logDebug:[NSString stringWithFormat:@"  sai_flags: %d",          (int)snp->sn_adaptation_event.sai_flags]];
                [self logDebug:[NSString stringWithFormat:@"  sai_length: %d",         (int)snp->sn_adaptation_event.sai_length]];
                [self logDebug:[NSString stringWithFormat:@"  sai_adaptation_ind: %d", (int)snp->sn_adaptation_event.sai_adaptation_ind]];
                [self logDebug:[NSString stringWithFormat:@"  sai_assoc_id: %d",       (int)snp->sn_adaptation_event.sai_assoc_id]];
            }
#endif
            break;
#endif
        case SCTP_PARTIAL_DELIVERY_EVENT:
            
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_PARTIAL_DELIVERY_EVENT"];
            }
#endif
            if(len < sizeof(struct sctp_pdapi_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_PARTIAL_DELIVERY_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
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
            break;
            
#ifdef SCTP_AUTHENTICATION_EVENT
        case SCTP_AUTHENTICATION_EVENT:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_AUTHENTICATION_EVENT"];
            }
#endif
            if(len < sizeof(struct sctp_authkey_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_AUTHENTICATION_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  auth_type: %d",           (int)snp->sn_auth_event.auth_type]];
                [self logDebug:[NSString stringWithFormat:@"  auth_flags: %d",          (int)snp->sn_auth_event.auth_flags]];
                [self logDebug:[NSString stringWithFormat:@"  auth_length: %d",         (int)snp->sn_auth_event.auth_length]];
                [self logDebug:[NSString stringWithFormat:@"  auth_keynumber: %d",      (int)snp->sn_auth_event.auth_keynumber]];
                [self logDebug:[NSString stringWithFormat:@"  auth_altkeynumber: %d",   (int)snp->sn_auth_event.auth_altkeynumber]];
                [self logDebug:[NSString stringWithFormat:@"  auth_indication: %d",     (int)snp->sn_auth_event.auth_indication]];
                [self logDebug:[NSString stringWithFormat:@"  auth_assoc_id: %d",       (int)snp->sn_auth_event.auth_assoc_id]];
            }
#endif
            break;
#endif
#ifdef SCTP_STREAM_RESET_EVENT
        case SCTP_STREAM_RESET_EVENT:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_STREAM_RESET_EVENT"];
            }
#endif
            if(len < sizeof(struct sctp_stream_reset_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_STREAM_RESET_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  strreset_type: %d",     (int)snp->sn_strreset_event.strreset_type]];
                [self logDebug:[NSString stringWithFormat:@"  strreset_flags: %d",    (int)snp->sn_strreset_event.strreset_flags]];
                [self logDebug:[NSString stringWithFormat:@"  strreset_length: %d",   (int)snp->sn_strreset_event.strreset_length]];
                [self logDebug:[NSString stringWithFormat:@"  strreset_assoc_id: %d", (int)snp->sn_strreset_event.strreset_assoc_id]];
            }
#endif
            break;
            
#endif
#ifdef SCTP_SENDER_DRY_EVENT
        case SCTP_SENDER_DRY_EVENT:
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_SENDER_DRY_EVENT"];
            }
#endif
            if(len < sizeof(struct sctp_sender_dry_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_SENDER_DRY_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
#if defined(ULIB_SCCTP_CAN_DEBUG)
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  sender_dry_type: %d",     (int)snp->sn_sender_dry_event.sender_dry_type]];
                [self logDebug:[NSString stringWithFormat:@"  sender_dry_flags: %d",    (int)snp->sn_sender_dry_event.sender_dry_flags]];
                [self logDebug:[NSString stringWithFormat:@"  sender_dry_length: %d",   (int)snp->sn_sender_dry_event.sender_dry_length]];
                [self logDebug:[NSString stringWithFormat:@"  sender_dry_assoc_id: %d", (int)snp->sn_sender_dry_event.sender_dry_assoc_id]];
            }
#endif
            break;
#endif
        default:
            [logFeed majorErrorText:[NSString stringWithFormat:@"SCTP unknown event type: %hu", snp->sn_header.sn_type]];
            [logFeed majorErrorText:[NSString stringWithFormat:@" RX-STREAM: %d",sinfo->sinfo_stream]];
            [logFeed majorErrorText:[NSString stringWithFormat:@" RX-PROTO: %d", ntohl(sinfo->sinfo_ppid)]];
            [logFeed majorErrorText:[NSString stringWithFormat:@" RX-DATA: %@",event.description]];
    }
    return 0;
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
        heartbeatMs = [cfg[@"heartbeat"] intValue];
    }
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
    config[@"heartbeat"] = @(heartbeatMs);
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
    d[@"msg-notification-mask"] = @(msg_notification_mask);
    d[@"heartbeat-in-ms"] = @(heartbeatMs);
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

@end
