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

- (UMLayerSctp *)initWithTaskQueueMulti:(UMTaskQueueMulti *)tq
{
    self = [super initWithTaskQueueMulti:tq];
    if(self)
    {
        fd = -1;
        timeoutInMs = 400;
        heartbeatMs = 30000;
        users = [[NSMutableArray alloc]init];
        self.status = SCTP_STATUS_OFF;
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
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"adminInit"]];
    }
}

- (void)_adminSetConfigTask:(UMSctpTask_AdminSetConfig *)task
{
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"setConfig %@",task.config]];
    }
    [self setConfig:task.config applicationContext:task.appContext];
}

- (void)_adminAttachTask:(UMSctpTask_AdminAttach *)task
{
    @synchronized(users)
    {
        id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;
        
        UMLayerSctpUser *u      = [[UMLayerSctpUser alloc]init];
        u.profile              = task.profile;
        u.user                  = user;
        u.userId                = task.userId;

        [users addObject:u];
        if(defaultUser==NULL)
        {
            defaultUser = u;
        }
        
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"attached %@",
                            user.layerName]];
        }
        [user adminAttachConfirm:self
                          userId:u.userId];
    }
}

- (void)_adminDetachTask:(UMSctpTask_AdminDetach *)task
{
    @synchronized(users)
    {
        for(UMLayerSctpUser *u in users)
        {
            if([u.userId isEqualTo:task.userId])
            {
                [users removeObject:u];
                [u.user adminDetachConfirm:self
                                  userId:u.userId];
                break;
            }
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
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"old open socket detected. closing it first"];
            }
            [self powerdown];
        }
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"socket()"]];
        }

        /**********************/
        /* SOCKET             */
        /**********************/
        [self logDebug:@"calling socket()"];
        self.fd = socket(AF_INET, SOCK_STREAM, IPPROTO_SCTP);
        [self logDebug:[NSString stringWithFormat:@" socket() returned fd=%d errno=%d",self.fd,errno]];
        if(self.fd < 0)
        {
            @throw([NSException exceptionWithName:@"socket()" reason:@"calling socket failed" userInfo:@{@"errno":@(errno),@"backtrace": UMBacktrace(NULL,0)}]);
        }
        [self logDebug:@"socket() successful"];

        /**********************/
        /* OPTIONS            */
        /**********************/
        
        [self setNonBlocking];
        
        setsockopt(self.fd, IPPROTO_SCTP, SCTP_NODELAY, (char *)&on, sizeof(on));
        setsockopt(self.fd, IPPROTO_SCTP, SCTP_REUSE_PORT, (char *)&on, sizeof(on));

        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@"enabling linger"];
        }
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
                    if(logLevel <= UMLOG_DEBUG)
                    {
                        [self logDebug:[NSString stringWithFormat:@"bind(%@:%d)",address,self.configured_local_port]];
                    }
                    err = bind(self.fd, (struct sockaddr *)&local_addr,sizeof(local_addr));
                    if(logLevel <= UMLOG_DEBUG)
                    {
                        [self logDebug:[NSString stringWithFormat:@"bind(%@:%d) returns %d (errno=%d)",address,self.configured_local_port,err,errno]];
                    }
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
                    if(logLevel <= UMLOG_DEBUG)
                    {
                        [self logDebug:[NSString stringWithFormat:@"sctp_bindx(%@)",address]];
                    }
                    err = sctp_bindx(self.fd, (struct sockaddr *)&local_addr,1,SCTP_BINDX_ADD_ADDR);
                    if(logLevel <= UMLOG_DEBUG)
                    {
                        [self logDebug:[NSString stringWithFormat:@"sctp_bindx(%@) returns %d (errno=%d)",address,err,errno]];
                    }
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
        
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"setsockopt() enabling events"]];
        }
        if (setsockopt(self.fd, IPPROTO_SCTP, SCTP_EVENTS, &event, sizeof(event)) != 0)
        {
            @throw([NSException exceptionWithName:@"EVENTS" reason:@"setsockoption failed to enable events" userInfo:@{@"errno":@(errno),@"backtrace": UMBacktrace(NULL,0)}]);
        }
        
        if(self.isPassive)
        {
            /**********************/
            /* LISTEN             */
            /**********************/
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"listen()"]];
            }
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
                close(self.fd);
                self.fd = newsock;
                [self setNonBlocking];
            }
        }
        else /* not passive */
        {
            /**********************/
            /* CONNECTX           */
            /**********************/
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"connectx()"]];
            }
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
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"started receiver thread"]];
            }
            self.status = SCTP_STATUS_OOS; /* we are CONNECTING but not yet CONNECTED. We are once the SCTP event up is received */
        }
    }
    @catch (NSException *exception)
    {
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"%@ %@",exception.name,exception.reason]];
        }
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
    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;
    if(logLevel <=UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"closing for %@",user.layerName]];
    }
    [self powerdown];
    [self reportStatus];
}


- (void)_dataTask:(UMSctpTask_Data *)task
{
    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;

    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"DATA: %@",task.data]];
        [self logDebug:[NSString stringWithFormat:@" streamId: %u",task.streamId]];
        [self logDebug:[NSString stringWithFormat:@" protocolId: %u",task.protocolId]];
        [self logDebug:[NSString stringWithFormat:@" ackRequest: %@",(task.ackRequest ? task.ackRequest.description  : @"(not present)")]];
    }

    @try
    {
        @synchronized(self)
        {

        }
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
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:@" Calling sctp_sendmsg"];
        }
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
        
        @synchronized(users)
        {
            for(UMLayerSctpUser *u in users)
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
        }

        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@" sent_packets: %ld",sent_packets]];
        }
        if(sent_packets >= 0)
        {
            NSDictionary *ui = @{
                                 @"protocolId" : @(task.protocolId),
                                 @"streamId"   : @(task.streamId),
                                 @"data"       : task.data
                                 };
            NSMutableDictionary *report = [task.ackRequest mutableCopy];
            [report setObject:ui forKey:@"sctp_data"];
            report[@"backtrace"] = UMBacktrace(NULL,0);
            [user sentAckConfirmFrom:self
                            userInfo:report];
        }
        else
        {
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
                default:
                    @throw([NSException exceptionWithName:[NSString stringWithFormat:@"ERROR %d",errno]
                                                   reason:[NSString stringWithFormat:@"unknown error %d",errno]
                                                 userInfo:@{@"backtrace": UMBacktrace(NULL,0)}]);
                    break;
            }
            [self powerdown];
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
    }
}


- (void)_foosTask:(UMSctpTask_Manual_ForceOutOfService *)task
{
    [self powerdown];
    self.status = SCTP_STATUS_M_FOOS;
    if(logLevel <=UMLOG_DEBUG)
    {
        [self logDebug:@"FOOS"];
    }
    [self reportStatus];
}

- (void)_isTask:(UMSctpTask_Manual_InService *)task
{
    id<UMLayerSctpUserProtocol> user = (id<UMLayerSctpUserProtocol>)task.sender;
    
    
    switch(self.status)
    {
        case SCTP_STATUS_M_FOOS:
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual M-FOOS->IS requested"];
            }
            self.status = SCTP_STATUS_OFF;
            [self reportStatus];
            [self openFor:user];
            break;
        case SCTP_STATUS_OFF:
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual OFF->IS requested"];
            }
            [self openFor:user];
            break;
        case SCTP_STATUS_OOS:
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual OOS->IS requested"];
            }
            [self reportStatus];
            break;
        case SCTP_STATUS_IS:
            if(logLevel <=UMLOG_DEBUG)
            {
                [self logDebug:@"manual IS->IS requested"];
            }
            [self reportStatus];
            break;
    }
}


#pragma mark -
#pragma mark Helpers

- (void) powerdown
{

    if(logLevel <= UMLOG_DEBUG)
    {
        [logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
    }
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
    if(logLevel <= UMLOG_DEBUG)
    {
        [logFeed debugText:[NSString stringWithFormat:@"powerdown"]];
    }
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
    @synchronized(users)
    {
        for(UMLayerSctpUser *u in users)
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

- (UMSocketError) dataIsAvailable
{
    struct pollfd pollfds[1];
    int ret1, ret2;
    
    memset(pollfds,0,sizeof(pollfds));
    pollfds[0].fd = fd;
    pollfds[0].events = POLLIN;
    UMAssert(timeoutInMs>0,@"timeout should be larger than 0");
    UMAssert(timeoutInMs<1000,@"timeout should be smaller than 1000ms");
    ret1 = poll(pollfds, 1, timeoutInMs);
    if (ret1 < 0)
    {
        if (errno != EINTR)
        {
            ret2 = [UMSocket umerrFromErrno:EBADF];
            return ret2;
        }
        else
        {
            return [UMSocket umerrFromErrno:errno];
        }
    }
    else if (ret1 == 0)
    {
        ret2 = UMSocketError_no_data;
        return ret2;
    }
    
    ret2 = pollfds[0].revents;
    if(ret2 & POLLERR)
    {
        return [UMSocket umerrFromErrno:errno];
    }
    else if(ret2 & POLLHUP)
    {
        return UMSocketError_has_data_and_hup;
    }
    else if(ret2 & POLLNVAL)
    {
        return [UMSocket umerrFromErrno:EBADF];
    }
    if((ret2 & POLLIN) || (ret2 & POLLPRI))
    {
        return UMSocketError_has_data;
    }
    return UMSocketError_no_data;
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
    if(logLevel <= UMLOG_DEBUG)
    {
        [self logDebug:[NSString stringWithFormat:@"FLAGS: 0x%08x",flags]];
    }

    NSData *data = [NSData dataWithBytes:&buffer length:bytes_read];

    if(flags & msg_notification_mask)
    {
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"RXT: got SCTP Notification of %u bytes", (unsigned int)bytes_read]];
        }
        return [self handleEvent:data sinfo:&sinfo];
    }
    else
    {
        if(logLevel <= UMLOG_DEBUG)
        {
            [self logDebug:[NSString stringWithFormat:@"RXT: got %u bytes on stream %hu protocol_id: %d",
                            (unsigned int)bytes_read,
                            sinfo.sinfo_stream,
                            ntohl(sinfo.sinfo_ppid)]];
        }
        if(defaultUser == NULL)
        {
            [self logDebug:@"RXT: USER instance not found. Maybe not bound yet?"];
            [self powerdownInReceiverThread];
            return -1;
        }
        /* if for whatever reason we have not realized we are in service yet, let us realize it now */
        if(self.status != SCTP_STATUS_IS)
        {
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"force change status to IS"]];
            }
            self.status = SCTP_STATUS_IS;
            [self reportStatus];
        }
        
        uint16_t streamId = sinfo.sinfo_stream;
        uint32_t protocolId = ntohl(sinfo.sinfo_ppid);
        
        @synchronized(users)
        {
            for(UMLayerSctpUser *u in users)
            {
                if( [u.profile wantsProtocolId:protocolId]
                 || [u.profile wantsStreamId:streamId])
                {
                    [self logDebug:[NSString stringWithFormat:@"passing data '%@' to USER[%@]",data.description,u.user.layerName]];
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
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_ASSOC_CHANGE"];
            }
            if(len < sizeof (struct sctp_assoc_change))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_ASSOC_CHANGE"];
                return -1;
            }
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
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_PEER_ADDR_CHANGE"];
            }
            if(len < sizeof (struct sctp_paddr_change))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_PEER_ADDR_CHANGE"];
                return -1;
            }
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  spc_type: %d",    (int)snp->sn_paddr_change.spc_type]];
                [self logDebug:[NSString stringWithFormat:@"  spc_flags: %d",   (int)snp->sn_paddr_change.spc_flags]];
                [self logDebug:[NSString stringWithFormat:@"  spc_length: %d",  (int)snp->sn_paddr_change.spc_length]];
            }
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
            break;
            
        case SCTP_REMOTE_ERROR:
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_REMOTE_ERROR"];
            }
            if(len < sizeof (struct sctp_remote_error))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_REMOTE_ERROR"];
                return -1;
            }
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
            break;
        case SCTP_SEND_FAILED:
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_SEND_FAILED"];
            }
            if(len < sizeof (struct sctp_send_failed))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_SEND_FAILED"];
                [self powerdownInReceiverThread];
                return -1;
            }
            [logFeed majorErrorText:@"SCTP_SEND_FAILED"];
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
            [logFeed majorErrorText:[NSString stringWithFormat:@"SCTP sendfailed: len=%du err=%d\n", snp->sn_send_failed.ssf_length,snp->sn_send_failed.ssf_error]];
            [self powerdownInReceiverThread];
            return -1;
            break;
        case SCTP_SHUTDOWN_EVENT:
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_SHUTDOWN_EVENT"];
            }
            if(len < sizeof (struct sctp_shutdown_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_SHUTDOWN_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  sse_type: %d",     (int)snp->sn_shutdown_event.sse_type]];
                [self logDebug:[NSString stringWithFormat:@"  sse_flags: %d",    (int)snp->sn_shutdown_event.sse_flags]];
                [self logDebug:[NSString stringWithFormat:@"  sse_length: %d",   (int)snp->sn_shutdown_event.sse_length]];
                [self logDebug:[NSString stringWithFormat:@"  sse_assoc_id: %d", (int)snp->sn_shutdown_event.sse_assoc_id]];
            }
            [logFeed warningText:@"SCTP_SHUTDOWN_EVENT->POWERDOWN"];
            [self powerdownInReceiverThread];
            return -1;
            break;
#ifdef	SCTP_ADAPTATION_INDICATION
        case SCTP_ADAPTATION_INDICATION:
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_ADAPTATION_INDICATION"];
            }
            if(len < sizeof(struct sctp_adaptation_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_ADAPTATION_INDICATION"];
                [self powerdownInReceiverThread];
                return -1;
            }
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  sai_type: %d",           (int)snp->sn_adaptation_event.sai_type]];
                [self logDebug:[NSString stringWithFormat:@"  sai_flags: %d",          (int)snp->sn_adaptation_event.sai_flags]];
                [self logDebug:[NSString stringWithFormat:@"  sai_length: %d",         (int)snp->sn_adaptation_event.sai_length]];
                [self logDebug:[NSString stringWithFormat:@"  sai_adaptation_ind: %d", (int)snp->sn_adaptation_event.sai_adaptation_ind]];
                [self logDebug:[NSString stringWithFormat:@"  sai_assoc_id: %d",       (int)snp->sn_adaptation_event.sai_assoc_id]];
            }
            break;
#endif
        case SCTP_PARTIAL_DELIVERY_EVENT:
            
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_PARTIAL_DELIVERY_EVENT"];
            }
            if(len < sizeof(struct sctp_pdapi_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_PARTIAL_DELIVERY_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
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
            break;
            
#ifdef SCTP_AUTHENTICATION_EVENT
        case SCTP_AUTHENTICATION_EVENT:
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_AUTHENTICATION_EVENT"];
            }
            if(len < sizeof(struct sctp_authkey_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_AUTHENTICATION_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
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
            break;
#endif
#ifdef SCTP_STREAM_RESET_EVENT
        case SCTP_STREAM_RESET_EVENT:
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_STREAM_RESET_EVENT"];
            }
            if(len < sizeof(struct sctp_stream_reset_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_STREAM_RESET_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  strreset_type: %d",     (int)snp->sn_strreset_event.strreset_type]];
                [self logDebug:[NSString stringWithFormat:@"  strreset_flags: %d",    (int)snp->sn_strreset_event.strreset_flags]];
                [self logDebug:[NSString stringWithFormat:@"  strreset_length: %d",   (int)snp->sn_strreset_event.strreset_length]];
                [self logDebug:[NSString stringWithFormat:@"  strreset_assoc_id: %d", (int)snp->sn_strreset_event.strreset_assoc_id]];
            }
            break;
            
#endif
#ifdef SCTP_SENDER_DRY_EVENT
        case SCTP_SENDER_DRY_EVENT:
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:@"SCTP_SENDER_DRY_EVENT"];
            }
            if(len < sizeof(struct sctp_sender_dry_event))
            {
                [logFeed majorErrorText:@" Size Mismatch in SCTP_SENDER_DRY_EVENT"];
                [self powerdownInReceiverThread];
                return -1;
            }
            if(logLevel <= UMLOG_DEBUG)
            {
                [self logDebug:[NSString stringWithFormat:@"  sender_dry_type: %d",     (int)snp->sn_sender_dry_event.sender_dry_type]];
                [self logDebug:[NSString stringWithFormat:@"  sender_dry_flags: %d",    (int)snp->sn_sender_dry_event.sender_dry_flags]];
                [self logDebug:[NSString stringWithFormat:@"  sender_dry_length: %d",   (int)snp->sn_sender_dry_event.sender_dry_length]];
                [self logDebug:[NSString stringWithFormat:@"  sender_dry_assoc_id: %d", (int)snp->sn_sender_dry_event.sender_dry_assoc_id]];
            }
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
        NSString *line = [cfg[@"local-ip"] stringValue];
        self.configured_local_addresses = [line componentsSeparatedByString:@" "];
    }
    if (cfg[@"local-port"])
    {
        configured_local_port = [cfg[@"local-port"] intValue];
    }
    if (cfg[@"remote-ip"])
    {
        NSString *line = [cfg[@"remote-ip"] stringValue];
        self.configured_remote_addresses = [line componentsSeparatedByString:@" "];
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

@end
