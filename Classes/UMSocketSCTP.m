//
//  UMSocketSCTP.m
//  ulibsctp
//
//  Created by Andreas Fink on 14.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#define ULIBSCTP_INTERNAL   1

#import "UMSocketSCTP.h"

#import "UMSocketSCTPListener.h"

#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/poll.h>
#include <arpa/inet.h>
#include <string.h>



#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/uio.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include <netinet/tcp.h>
#include <netdb.h>

#ifdef __APPLE__
#import <sctp/sctp.h>
#include <sys/utsname.h>

#define MSG_NOTIFICATION_MAVERICKS 0x40000        /* notification message */
#define MSG_NOTIFICATION_YOSEMITE  0x80000        /* notification message */
#if defined __APPLE__
#define ULIBSCTP_SCTP_SENDV_SUPPORTED 1
#define ULIBSCTP_SCTP_RECVV_SUPPORTED 1
#endif

#else
#include <netinet/sctp.h>
#endif

#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netdb.h>
#include <sys/utsname.h>


static int _global_msg_notification_mask = 0;

/*
int sctp_sendv(int s, const struct iovec *iov, int iovcnt,
               struct sockaddr *addrs, int addrcnt, void *info,
               socklen_t infolen, unsigned int infotype, int flags);


int sctp_recvv(int s, const struct iovec *iov, int iovlen,
               struct sockaddr *from, socklen_t *fromlen, void *info,
               socklen_t *infolen, unsigned int *infotype, int *flags);
*/

@implementation UMSocketSCTP

- (void)initNetworkSocket
{
    _historyLog = [[UMHistoryLog alloc]initWithMaxLines:100];
    _sock = -1;
    switch(type)
    {
        case UMSOCKET_TYPE_SCTP4ONLY_SEQPACKET:
            _socketFamily=AF_INET;
            _socketType = SOCK_SEQPACKET;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP6ONLY_SEQPACKET:
            _socketFamily=AF_INET6;
            _socketType = SOCK_SEQPACKET;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP_SEQPACKET:
            _socketFamily=AF_INET6;
            _socketType = SOCK_SEQPACKET;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            if(_sock < 0)
            {
                if(errno==EAFNOSUPPORT)
                {
                    _socketFamily=AF_INET;
                    _sock = socket(_socketFamily,_socketType, _socketProto);
                    TRACK_FILE_SOCKET(_sock,@"sctp");
                    if(_sock!=-1)
                    {
                        int flags = 1;
                        setsockopt(_sock, IPPROTO_SCTP, SCTP_NODELAY, (char *)&flags, sizeof(flags));
                    }
                }
            }
            break;
        case UMSOCKET_TYPE_SCTP4ONLY_STREAM:
            _socketFamily=AF_INET;
            _socketType = SOCK_STREAM;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP6ONLY_STREAM:
            _socketFamily=AF_INET6;
            _socketType = SOCK_STREAM;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP_STREAM:
            _socketFamily=AF_INET6;
            _socketType = SOCK_STREAM;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            if(_sock < 0)
            {
                if(errno==EAFNOSUPPORT)
                {
                    _socketFamily=AF_INET;
                    _sock = socket(_socketFamily,_socketType, _socketProto);
                    TRACK_FILE_SOCKET(_sock,@"sctp");
                    if(_sock!=-1)
                    {
                        int flags = 1;
                        setsockopt(_sock, IPPROTO_SCTP, SCTP_NODELAY, (char *)&flags, sizeof(flags));
                    }
                }
            }
            break;
        case UMSOCKET_TYPE_SCTP4ONLY_DGRAM:
            _socketFamily=AF_INET;
            _socketType = SOCK_DGRAM;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP6ONLY_DGRAM:
            _socketFamily=AF_INET6;
            _socketType = SOCK_DGRAM;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP_DGRAM:
            _socketFamily=AF_INET6;
            _socketType = SOCK_DGRAM;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            if(_sock < 0)
            {
                if(errno==EAFNOSUPPORT)
                {
                    _socketFamily=AF_INET;
                    _sock = socket(_socketFamily,_socketType, _socketProto);
                    TRACK_FILE_SOCKET(_sock,@"sctp");
                    if(_sock!=-1)
                    {
                        int flags = 1;
                        setsockopt(_sock, IPPROTO_SCTP, SCTP_NODELAY, (char *)&flags, sizeof(flags));
                    }
                }
            }
            break;

        default:
            [super initNetworkSocket];
            break;
    }
    if(_sock > -1)
    {
        _hasSocket = YES;
    }
    else
    {
        _hasSocket = NO;
    }
    
    if(_global_msg_notification_mask==0)
    {
#ifdef __APPLE__
        int major;
        int minor;
        int sub;
        
        struct utsname ut;
        uname(&ut);
        sscanf(ut.release,"%d.%d.%d",&major,&minor,&sub);
        if(major >= 14)
        {
            _global_msg_notification_mask = MSG_NOTIFICATION_YOSEMITE;
        }
        else
        {
            _global_msg_notification_mask = MSG_NOTIFICATION_MAVERICKS;
        }
#else
        _global_msg_notification_mask = MSG_NOTIFICATION;
#endif
    }
    _msg_notification_mask = _global_msg_notification_mask;
    status = UMSOCKET_STATUS_FOOS;
}





- (void)prepareLocalAddresses
{
    if((_localAddressesSockaddr==NULL) || ( _localAddressesSockaddrCount==0))
    {
        int  _localAddressesSockaddrCount;
        _localAddressesSockaddr = [UMSocketSCTP sockaddrFromAddresses:_requestedLocalAddresses
                                                                 port:self.requestedLocalPort
                                                                count:&_localAddressesSockaddrCount /* returns struct sockaddr data in NSData */
                                                         socketFamily:AF_INET6];
    }
}

- (UMSocketError) bind
{
    NSMutableArray *useable_local_addr = [[NSMutableArray alloc]init];

    if((_localAddressesSockaddr==NULL) || ( _localAddressesSockaddrCount==0))
    {
        _localAddressesSockaddr = [UMSocketSCTP sockaddrFromAddresses:_requestedLocalAddresses
                                                                 port:self.requestedLocalPort
                                                                count:&_localAddressesSockaddrCount /* returns struct sockaddr data in NSData */
                                                         socketFamily:_socketFamily];
    }
    /* at this point usable_addresses contains strings which are in _socketFamily specific formats */
    /* invalid IP's have been remvoed */
    int usable_ips = -1;

    for(int i=0;i<_localAddressesSockaddrCount;i++)
    {
        struct sockaddr *localAddress = NULL;
        if(_socketFamily == AF_INET6)
        {
            struct sockaddr_in6 *local_addresses=(struct sockaddr_in6 *)_localAddressesSockaddr.bytes;
            localAddress = (struct sockaddr *)&local_addresses[i];
        }
        else
        {
            struct sockaddr_in *local_addresses=(struct sockaddr_in *)_localAddressesSockaddr.bytes;
            localAddress = (struct sockaddr *)&local_addresses[i];
        }
        NSString *addr = [UMSocket addressOfSockAddr:localAddress];
        if(usable_ips == -1)
        {
#if defined(ULIBSCTP_CONFIG_DEBUG)
            int port = [UMSocket portOfSockAddr:localAddress];
            NSLog(@"calling bind for '%@:%d' on socket %d",addr,port,_sock);
#endif
            int err;
            if(_socketFamily == AF_INET6)
            {
                err = bind(_sock, localAddress,sizeof(struct sockaddr_in6));
            }
            else
            {
                err = bind(_sock, localAddress,sizeof(struct sockaddr_in));
            }
            if(err==0)
            {
#if defined(ULIBSCTP_CONFIG_DEBUG)
                NSLog(@" bind succeeds for %@:%d",addr,_requestedLocalPort);
#endif
                usable_ips = 1;
                [useable_local_addr addObject:addr];
            }
            else
            {
                NSLog(@" bind returns error %d %s for %@",errno,strerror(errno),addr);
            }
        }
        else
        {
#if defined(ULIBSCTP_CONFIG_DEBUG)
            int port = [UMSocket portOfSockAddr:localAddress];
            NSLog(@"calling sctp_bindx for '%@:%d'",addr,port);
#endif
            int err = [self bindx:localAddress];
            if(err==0)
            {
#if defined(ULIBSCTP_CONFIG_DEBUG)
                NSLog(@" sctp_bindx succeeds for %@",addr);
#endif
                usable_ips++;
                [useable_local_addr addObject:addr];
            }
            else
            {
                NSLog(@" sctp_bindx returns error %d %s for %@",errno,strerror(errno),addr);
            }
        }
    }
    if(usable_ips <= 0)
    {
        [_historyLog addLogEntry:@"bind: no usable IPs"];
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"bind(SCTP): usable_ips=%d",usable_ips);
#endif
        return UMSocketError_address_not_available;
    }
    else
    {
        NSString *s = [useable_local_addr componentsJoinedByString:@","];
        s = [NSString stringWithFormat:@"bind: %@",s];
        [_historyLog addLogEntry:s];
    }
    _useableLocalAddresses = useable_local_addr;
    return UMSocketError_no_error;
}

- (UMSocketError) enableEvents
{
    struct sctp_event_subscribe event;
    
    /**********************/
    /* ENABLING EVENTS    */
    /**********************/

    [_historyLog addLogEntry:@"enableEvents"];
    memset((void *)&event,0x00, sizeof(struct sctp_event_subscribe));
    event.sctp_data_io_event            = 1;
    event.sctp_association_event        = 1;
    event.sctp_address_event            = 1;
    event.sctp_send_failure_event       = 1;
    event.sctp_peer_error_event         = 1;
    event.sctp_shutdown_event           = 1;
    event.sctp_partial_delivery_event   = 1;
    event.sctp_adaptation_layer_event   = 1;
//    event.sctp_authentication_event     = 1;
#ifndef LINUX
    event.sctp_stream_reset_events      = 1;
#endif
    if(setsockopt(_sock, IPPROTO_SCTP, SCTP_EVENTS, &event, sizeof(event)) != 0)
    {
        return [UMSocket umerrFromErrno:errno];
    }
    return UMSocketError_no_error;
}

- (int)mtu
{
    return _mtu;
}

- (void)setMtu:(int)newMtu
{
    [_historyLog addLogEntry:[NSString stringWithFormat:@"setMtu:%d",newMtu]];
    _mtu = newMtu;
    struct sctp_paddrparams params;
    socklen_t len = sizeof(params);

    memset((void *)&params,0x00, sizeof(struct sctp_paddrparams));
    if(getsockopt(_sock, IPPROTO_SCTP, SCTP_PEER_ADDR_PARAMS, &params, &len) == 0)
    {
        if(newMtu > 0)
        {
            if(_socketFamily == AF_INET)
            {
                struct sockaddr_in *sa = (struct sockaddr_in *)&params.spp_address;
                memset(sa,0x00,sizeof(struct sockaddr_in));
                sa->sin_family = AF_INET;
#ifdef    HAS_SOCKADDR_LEN
                sa->sin_len = sizeof(struct sockaddr_in);
#endif
                sa->sin_addr.s_addr = htonl(INADDR_ANY);
            }
            else if(_socketFamily == AF_INET6)
            {
                struct sockaddr_in6 *sa6 = (struct sockaddr_in6 *)&params.spp_address;
                memset(sa6,0x00,sizeof(struct sockaddr_in6));
                sa6->sin6_family = AF_INET6;
#ifdef    HAS_SOCKADDR_LEN
                sa6->sin6_len = sizeof(struct sockaddr_in6);
#endif
                sa6->sin6_addr = in6addr_any;
            }
            params.spp_pathmtu = newMtu;
            params.spp_flags &= ~SPP_PMTUD_ENABLE;
            params.spp_flags |= SPP_PMTUD_DISABLE;
        }
        else
        {
            params.spp_flags &= ~SPP_PMTUD_DISABLE;
            params.spp_flags |= SPP_PMTUD_ENABLE;
        }

        if(setsockopt(_sock, IPPROTO_SCTP, SCTP_PEER_ADDR_PARAMS, &params, len) == 0)
        {
            if(getsockopt(_sock, IPPROTO_SCTP, SCTP_PEER_ADDR_PARAMS, &params, &len) == 0)
            {
                if(params.spp_flags & SPP_PMTUD_DISABLE)
                {
                    _mtu = params.spp_pathmtu;
                }
                else
                {
                    _mtu = 0;
                }
            }
        }
    }
}


- (UMSocketError)setHeartbeat:(BOOL)enable
{
    if(enable)
    {
        [_historyLog addLogEntry:@"enable heartbeat"];
    }
    else
    {
        [_historyLog addLogEntry:@"disable heartbeat"];
    }
    struct sctp_paddrparams heartbeat;
    socklen_t len = sizeof(heartbeat);

    memset((void *)&heartbeat,0x00, sizeof(struct sctp_paddrparams));
    if(getsockopt(_sock, IPPROTO_SCTP, SCTP_PEER_ADDR_PARAMS, &heartbeat, &len) == 0)
    {
        if(_socketFamily == AF_INET)
        {
            struct sockaddr_in *sa = (struct sockaddr_in *)&heartbeat.spp_address;
            memset(sa,0x00,sizeof(struct sockaddr_in));
            sa->sin_family = AF_INET;
#ifdef    HAS_SOCKADDR_LEN
            sa->sin_len = sizeof(struct sockaddr_in);
#endif
            sa->sin_addr.s_addr = htonl(INADDR_ANY);
        }
        else if(_socketFamily == AF_INET6)
        {
            struct sockaddr_in6 *sa6 = (struct sockaddr_in6 *)&heartbeat.spp_address;
            memset(sa6,0x00,sizeof(struct sockaddr_in6));
            sa6->sin6_family = AF_INET6;
#ifdef    HAS_SOCKADDR_LEN
            sa6->sin6_len = sizeof(struct sockaddr_in6);
#endif
            sa6->sin6_addr = in6addr_any;
        }
        if(enable)
        {
            heartbeat.spp_flags = SPP_HB_ENABLE;
            heartbeat.spp_hbinterval = 30000;
            heartbeat.spp_pathmaxrxt = 1;
        }
        else
        {
            heartbeat.spp_flags = SPP_HB_DISABLE;
            heartbeat.spp_hbinterval = 30000;
            heartbeat.spp_pathmaxrxt = 1;
        }
        if(setsockopt(_sock, IPPROTO_SCTP, SCTP_PEER_ADDR_PARAMS , &heartbeat, sizeof(heartbeat)) != 0)
        {
            return [UMSocket umerrFromErrno:errno];
        }
        return UMSocketError_no_error;
    }
    if(errno)
    {
        [_historyLog addLogEntry:[NSString stringWithFormat:@"errno=%d %s",errno,strerror(errno)]];
    }
    return [UMSocket umerrFromErrno:errno];
}


- (int)maxSegment
{
    return _maxSeg;
}

- (void)setMaxSegment:(int)newMaxSeg
{
    int disableFragments = 0;
    if(newMaxSeg > 0)
    {
        disableFragments = 1;
    }
    setsockopt(_sock,IPPROTO_SCTP,SCTP_DISABLE_FRAGMENTS, &disableFragments, sizeof(int));
    setsockopt(_sock,IPPROTO_SCTP,SCTP_MAXSEG, &newMaxSeg, sizeof(int));
    
    [_historyLog addLogEntry:[NSString stringWithFormat:@"setMaxSegment %d errno=%d %s",newMaxSeg,errno,strerror(errno)]];

    _maxSeg = newMaxSeg;
}

- (void)updateMtu:(int)newMtu
{
/* to mitigate kernel panic in some versions
     https://www.spinics.net/lists/netdev/msg534371.html
*/
    if(newMtu==0)
    {
        [self setMtu:1500];
        [self setMtu:0];
    }
    else
    {
        [self setMtu:0];
        [self setMtu:newMtu];
    }
}

- (UMSocketError) enableFutureAssoc
{
#if defined(SCTP_FUTURE_ASSOC) && defined(SCTP_ADAPTATION_INDICATION)
    struct sctp_event event;
    UMSocketError r = UMSocketError_no_error;
    /* Enable the events of interest. */
    memset(&event, 0, sizeof(event));
    event.se_assoc_id = SCTP_FUTURE_ASSOC;
    event.se_on = 1;
    event.se_type = SCTP_ADAPTATION_INDICATION;
    if (setsockopt(_sock, IPPROTO_SCTP, SCTP_EVENT, &event, sizeof(event)) < 0)
    {
        r = [UMSocket umerrFromErrno:errno];
    }
    [_historyLog addLogEntry:[NSString stringWithFormat:@"enableFutureAssoc: errno=%d %s",errno,strerror(errno)]];
#endif
    return r;

}



+ (NSData *)sockaddrFromAddresses:(NSArray *)theAddrs
                             port:(int)thePort
                            count:(int *)count_out /* returns struct sockaddr data in NSData */
                     socketFamily:(int)socketFamily
{
    struct sockaddr_in6 *addresses6=NULL;
    struct sockaddr_in  *addresses4=NULL;
    struct sockaddr     *addresses46 = NULL;
    size_t              addresses46_len = 0;

    int count = (int)theAddrs.count;

    int j=0;
    if(socketFamily==AF_INET6)
    {
        addresses6 = calloc(count,sizeof(struct sockaddr_in6));
        for(int i=0;i<count;i++)
        {
            NSString *address = [theAddrs objectAtIndex:i];
            NSString *address2 = [UMSocket deunifyIp:address];
            if(address2.length>0)
            {
                address = address2;
            }
            if([address isIPv4])
            {
                /* we have a IPV6 socket but the remote addres is in IPV4 format so we must use the IPv6 representation of it */
                address =[NSString stringWithFormat:@"::ffff:%@",address];
            }
            int result = inet_pton(AF_INET6,address.UTF8String, &addresses6[j].sin6_addr);
            if(result==1)
            {
#ifdef HAVE_SOCKADDR_SIN_LEN
                addresses6[j].sin6_len = sizeof(struct sockaddr_in6);
#endif
                addresses6[j].sin6_family = AF_INET6;
                addresses6[j].sin6_port = htons(thePort);
                j++;
            }
            else
            {
                NSLog(@"%@ is not a valid IP address. skipped ",address);
            }
        }
        if(j==0)
        {
            NSLog(@"no valid local IP addresses found %@:%d AF_INET6",[theAddrs componentsJoinedByString:@","],thePort);
            free(addresses6);
            addresses6 = NULL;
            *count_out = 0;
        }
        else
        {
            if(j<count)
            {
                addresses6 = realloc(addresses6,sizeof(struct sockaddr_in6)*j);
                count = j;
            }
            addresses46 = (struct sockaddr *)addresses6;
            addresses46_len = sizeof(struct sockaddr_in6)*count;
        }
    }
    else if(socketFamily==AF_INET)
    {
        addresses4 = calloc(count,sizeof(struct sockaddr_in));
        for(int i=0;i<count;i++)
        {
            NSString *address = [theAddrs objectAtIndex:i];
            NSString *address2 = [UMSocket deunifyIp:address];
            if(address2.length>0)
            {
                address = address2;
            }
            int result = inet_pton(AF_INET,address.UTF8String, &addresses4[j].sin_addr);
            if(result==1)
            {
#ifdef HAVE_SOCKADDR_SIN_LEN
                addresses4[j].sin_len = sizeof(struct sockaddr_in);
#endif
                addresses4[j].sin_family = AF_INET;
                addresses4[j].sin_port = htons(thePort);
                j++;
            }
            else
            {
                NSLog(@"'%@' is not a valid IP address. skipped ",address);
            }
        }
        if(j==0)
        {
            NSLog(@"no valid local IP addresses found %@:%d AF_INET",[theAddrs componentsJoinedByString:@","],thePort);
            free(addresses4);
        }
        else
        {
            if(j<count)
            {
                addresses4 = realloc(addresses4,sizeof(struct sockaddr_in)*j);
                count = j;
            }
            addresses46 = (struct sockaddr *)addresses4;
            addresses46_len = sizeof(struct sockaddr_in)*count;
        }
    }
    if(count_out)
    {
        *count_out = count;
    }
    NSData *result = [NSData dataWithBytes:addresses46 length:addresses46_len];
    free(addresses46);
    return result;
}

- (UMSocketError) connect
{
    uint32_t assoc;

    UMSocketError e = [self connectToAddresses:_requestedRemoteAddresses
                        port:_requestedRemotePort
                       assoc:&assoc];
    return e;
}

- (UMSocketError) connectAssoc:(uint32_t *)assoc;
{
    UMSocketError e = [self connectToAddresses:_requestedRemoteAddresses
                                          port:_requestedRemotePort
                                         assoc:assoc];
    return e;
}

- (UMSocketError) connectToAddresses:(NSArray *)addrs
                                port:(int)remotePort
                               assoc:(uint32_t *)assocptr
{
	UMAssert(assocptr!=NULL,@"assocptr can not be NULL");

    sctp_assoc_t assoc = -1;

    int count = 0;
    NSData *remote_sockaddr = [UMSocketSCTP sockaddrFromAddresses:addrs port:remotePort count:&count socketFamily:_socketFamily]; /* returns struct sockaddr data in NSData */

    /**********************/
    /* CONNECTX           */
    /**********************/
    UMSocketError returnValue = UMSocketError_no_error;

    if(count<1)
    {
        self.status = UMSOCKET_STATUS_OFF;
        returnValue = UMSocketError_address_not_available;
    }
    else
    {
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"calling sctp_connectx (%@)", [addrs componentsJoinedByString:@" "]);
#endif
        memset(assocptr,0,sizeof(sctp_assoc_t));
        assoc = -1;
        int err =  sctp_connectx(_sock,(struct sockaddr *)remote_sockaddr.bytes,count,&assoc);
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"sctp_connectx: returns %d. errno = %d %s assoc=%lu",err,errno,strerror(errno),(unsigned long)*assocptr);
#endif
        if(assocptr && assoc != -1)
        {
            *assocptr = (uint32_t)assoc;
#if defined(ULIBSCTP_CONFIG_DEBUG)
            NSLog(@"assoc is now set to %lu", (unsigned long)assoc);
#endif
        }
        _connectedRemotePort = remotePort;

        if (err < 0)
        {
            returnValue = [UMSocket umerrFromErrno:errno];
			if(errno==EINPROGRESS)
			{
				_connectx_pending = YES;
                self.status = UMSOCKET_STATUS_OOS;
			}
        }
        else
        {
            _connectx_pending = YES;
            self.status = UMSOCKET_STATUS_IS;
            returnValue = UMSocketError_no_error;
        }
    }
    
    [_historyLog addLogEntry:[NSString stringWithFormat:@"connect(%@:%d) assoc=%lu %@",
                           [addrs componentsJoinedByString:@","],
                           remotePort,
                           (unsigned long)assoc,
                           [UMSocket getSocketErrorString:returnValue]]];
    return returnValue;
}

/* overloading accept */
- (UMSocketSCTP *) accept:(UMSocketError *)ret
{
    return [self acceptSCTP:ret];
}

- (UMSocketSCTP *) acceptSCTP:(UMSocketError *)ret
{
    int           newsock = -1;
    UMSocketSCTP  *newcon =NULL;
    NSString *remoteAddress=@"";
    in_port_t remotePort=0;
    if(type == UMSOCKET_TYPE_SCTP4ONLY_SEQPACKET)
    {
        struct    sockaddr_in sa4;
        socklen_t slen4 = sizeof(sa4);
        [_controlLock lock];
        newsock = accept(_sock,(struct sockaddr *)&sa4,&slen4);
        [_controlLock unlock];

        if(newsock >=0)
        {
            char hbuf[NI_MAXHOST];
            char sbuf[NI_MAXSERV];
            if (getnameinfo((struct sockaddr *)&sa4, slen4, hbuf, sizeof(hbuf), sbuf,
                            sizeof(sbuf), NI_NUMERICHOST | NI_NUMERICSERV))
            {
                remoteAddress = @"ipv4:0.0.0.0";
                remotePort = 0;
            }
            else
            {
                remoteAddress = @(hbuf);
                remoteAddress = [NSString stringWithFormat:@"ipv4:%@", remoteAddress];
                remotePort = sa4.sin_port;
            }
            TRACK_FILE_SOCKET(newsock,remoteAddress);
            newcon.cryptoStream.fileDescriptor = newsock;
        }
    }
    else
    {
        /* IPv6 or dual mode */
        struct    sockaddr_in6        sa6;
        socklen_t slen6 = sizeof(sa6);
        memset(&sa6,0x00,slen6);
        sa6.sin6_port = htons(3868);
        [_controlLock lock];
        newsock = accept(_sock,(struct sockaddr *)&sa6,&slen6);
        [_controlLock unlock];

        if(newsock >= 0)
        {
            char hbuf[NI_MAXHOST], sbuf[NI_MAXSERV];
            if (getnameinfo((struct sockaddr *)&sa6, slen6, hbuf, sizeof(hbuf), sbuf,
                            sizeof(sbuf), NI_NUMERICHOST | NI_NUMERICSERV))
            {
                remoteAddress = @"ipv6:[::]";
                remotePort = 0;
            }
            else
            {
                remoteAddress = @(hbuf);
                remotePort = sa6.sin6_port;
            }
            /* this is a IPv4 style address packed into IPv6 */
            
            remoteAddress = [UMSocket unifyIP:remoteAddress];
            TRACK_FILE_SOCKET(newsock,remoteAddress);
        }
    }
    
    if(newsock >= 0)
    {
        newcon = [[UMSocketSCTP alloc]init];
        newcon.type = type;
        newcon.socketFamily = self.socketFamily;
        newcon.direction =  direction;
        newcon.status=UMSOCKET_STATUS_IS;
        newcon.localHost = self.localHost;
        newcon.remoteHost = self.remoteHost;
        newcon.requestedLocalAddresses = _requestedLocalAddresses;
        newcon.requestedLocalPort=self.requestedLocalPort;
        newcon.requestedRemoteAddresses = _requestedRemoteAddresses;
        newcon.requestedRemotePort=self.requestedRemotePort;

		newcon.connectedLocalAddresses = _connectedLocalAddresses;
		newcon.connectedLocalPort=self.connectedLocalPort;
		newcon.connectedRemoteAddresses = _connectedRemoteAddresses;
		newcon.connectedRemotePort=self.connectedRemotePort;

        newcon.cryptoStream = [[UMCrypto alloc]initWithRelatedSocket:newcon];
        newcon.isBound=NO;
        newcon.isListening=NO;
        newcon.isConnecting=NO;
        newcon.isConnected=YES;
        [newcon setSock: newsock];
        [newcon switchToNonBlocking];
        [newcon doInitReceiveBuffer];
        newcon.connectedRemoteAddress = remoteAddress;
        newcon.connectedRemotePort = remotePort;
        newcon.useSSL = useSSL;
        [newcon updateMtu:_mtu];
        [newcon updateName];
        newcon.objectStatisticsName = @"UMSocket(accept)";
        newcon.historyLog = [[UMHistoryLog alloc]initWithMaxLines:100];
        [self reportStatus:@"accept () successful"];
        /* TODO: start SSL if required here */
        *ret = UMSocketError_no_error;
        return newcon;
    }
    *ret = [UMSocket umerrFromErrno:errno];
    return nil;
}

- (UMSocketSCTP *) peelOffAssoc:(uint32_t)assoc
                          error:(UMSocketError *)errptr
{

#if defined(ULIBSCTP_CONFIG_DEBUG)
    NSLog(@"calling peelOffAssoc:(assoc=%d)",assoc);
#endif
    int           newsock = -1;
    UMSocketSCTP  *newcon =NULL;
    NSString *remoteAddress=@"";
    in_port_t remotePort=0;
    if(type == UMSOCKET_TYPE_SCTP4ONLY_SEQPACKET)
    {
        struct    sockaddr_in sa4;
        socklen_t slen4 = sizeof(sa4);
        memset(&sa4,0x00,slen4);
        [_controlLock lock];
        newsock = sctp_peeloff(_sock,assoc);
        [_controlLock unlock];

        if(newsock >=0)
        {
            char hbuf[NI_MAXHOST];
            char sbuf[NI_MAXSERV];
            if (getnameinfo((struct sockaddr *)&sa4, slen4, hbuf, sizeof(hbuf), sbuf,
                            sizeof(sbuf), NI_NUMERICHOST | NI_NUMERICSERV))
            {
                remoteAddress = @"ipv4:0.0.0.0";
                remotePort = 0;
            }
            else
            {
                remoteAddress = @(hbuf);
                remoteAddress = [NSString stringWithFormat:@"ipv4:%@", remoteAddress];
                remotePort = sa4.sin_port;
            }
            TRACK_FILE_SOCKET(newsock,remoteAddress);
            newcon.cryptoStream.fileDescriptor = newsock;
        }
    }
    else
    {
        /* IPv6 or dual mode */
        struct    sockaddr_in6        sa6;
        socklen_t slen6 = sizeof(sa6);
        memset(&sa6,0x00,slen6);

        [_controlLock lock];
        newsock = sctp_peeloff(_sock,assoc);
        [_controlLock unlock];

        if(newsock >= 0)
        {
            char hbuf[NI_MAXHOST], sbuf[NI_MAXSERV];
            if (getnameinfo((struct sockaddr *)&sa6, slen6, hbuf, sizeof(hbuf), sbuf,
                            sizeof(sbuf), NI_NUMERICHOST | NI_NUMERICSERV))
            {
                remoteAddress = @"ipv6:[::]";
                remotePort = 0;
            }
            else
            {
                remoteAddress = @(hbuf);
                remotePort = sa6.sin6_port;
            }
            /* this is a IPv4 style address packed into IPv6 */

            remoteAddress = [UMSocket unifyIP:remoteAddress];
            TRACK_FILE_SOCKET(newsock,remoteAddress);
        }
    }

    if(newsock >= 0)
    {
        newcon = [[UMSocketSCTP alloc]init];
        newcon.type = type;
		newcon.socketDomain = _socketDomain;
		newcon.socketFamily = _socketFamily;
		newcon.socketType = _socketType;
		newcon.socketProto = _socketProto;
        newcon.xassoc = @(assoc);
		[newcon initNetworkSocket];

		newcon.configuredMaxSegmentSize = _configuredMaxSegmentSize;
		int activeSctpMaxSegmentSize = 0;

        struct sctp_assoc_value a;
        a.assoc_id = assoc;
        a.assoc_value = 0;

        socklen_t maxseg_len = sizeof(a);

		if(getsockopt(_sock, IPPROTO_SCTP, SCTP_MAXSEG, &a, &maxseg_len) == 0)
		{
			newcon.activeMaxSegmentSize = a.assoc_value;
			if((_configuredMaxSegmentSize > 0) && (_configuredMaxSegmentSize < activeSctpMaxSegmentSize))
			{
                newcon.activeMaxSegmentSize = _configuredMaxSegmentSize;
				if(setsockopt(_sock, IPPROTO_SCTP, SCTP_MAXSEG, &activeSctpMaxSegmentSize, maxseg_len))
				{
                    if(getsockopt(_sock, IPPROTO_SCTP, SCTP_MAXSEG, &a, &maxseg_len) == 0)
                    {
                        newcon.activeMaxSegmentSize = a.assoc_value;
                    }
				}
			}
		}

        newcon.direction =  direction;
        newcon.status=status;
        newcon.localHost = self.localHost;
        newcon.remoteHost = self.remoteHost;
        newcon.requestedLocalAddresses = _requestedLocalAddresses;
        newcon.requestedLocalPort=_requestedLocalPort;
        newcon.requestedRemoteAddresses = _requestedRemoteAddresses;
        newcon.requestedRemotePort=_requestedRemotePort;
		newcon.connectedLocalAddresses = _connectedLocalAddresses;
		newcon.connectedLocalPort = _connectedLocalPort;
		newcon.connectedRemoteAddresses = @[remoteAddress];
		newcon.connectedRemotePort = remotePort;
        newcon.cryptoStream = [[UMCrypto alloc]initWithRelatedSocket:newcon];
        newcon.isBound=NO;
        newcon.isListening=NO;
        newcon.isConnecting=NO;
        newcon.isConnected=YES;
        [newcon setSock: newsock];
        [newcon switchToNonBlocking];
        [newcon doInitReceiveBuffer];
        newcon.useSSL = useSSL;
        [newcon updateMtu:_mtu];
        [newcon updateName];
        newcon.objectStatisticsName = @"UMSocket(accept)";
        [self reportStatus:@"accept () successful"];
        /* TODO: start SSL if required here */
        if(*errptr)
        {
            *errptr = UMSocketError_no_error;
        }
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"   returning new socket/UMSocketError_no_error");
#endif
        return newcon;
    }

    UMSocketError e = [UMSocket umerrFromErrno:errno];

    if(*errptr)
    {
        *errptr = e;
    }

#if defined(ULIBSCTP_CONFIG_DEBUG)
    NSLog(@"   returning nil/err = %@",[UMSocket getSocketErrorString:e]);
#endif
    return nil;
}

- (ssize_t) sendToAddresses:(NSArray *)addrs
                       port:(int)remotePort
                      assoc:(uint32_t *)assocptr
                       data:(NSData *)data
                     stream:(uint16_t)streamId
                   protocol:(u_int32_t)protocolId
                      error:(UMSocketError *)err2
{
	UMAssert(assocptr!=NULL,@"assocptr can not be NULL");
    UMSocketError err = UMSocketError_no_error;

    ssize_t sp = 0;
    if(data == NULL)
    {
        if(err2)
        {
            *err2 = UMSocketError_no_data;
        }
        return -1;
    }

    if(*assocptr == -1)
    {
        err = [self connectToAddresses:addrs
                                  port:remotePort
                                 assoc:assocptr];
        if(err==UMSocketError_is_already_connected)
        {
            err = UMSocketError_no_error;
            *err2 =err;
        }
        if(err!= UMSocketError_is_already_connected)
        {
            err = UMSocketError_no_error;
            if(err2)
            {
                *err2 = err;
            }
        }
        else if((err != UMSocketError_no_error) && (err != UMSocketError_in_progress) )
        {
            if(err2)
            {
                *err2 = err;
            }
            return -1;
        }
    }
    if (*assocptr==-1)
    {
        if(err2)
        {
            *err2 = UMSocketError_address_not_available;
        }
		return -1;
    }

	int count = 0;
	int flags=0;

	NSData *remote_sockaddr = [UMSocketSCTP sockaddrFromAddresses:addrs port:remotePort count:&count socketFamily:_socketFamily]; /* returns struct sockaddr data in NSData */

    [UMSocketSCTP sockaddrFromAddresses:addrs port:remotePort count:&count socketFamily:_socketFamily];
#if defined(ULIBSCTP_SCTP_SENDV_SUPPORTED)


    struct iovec iov[1];
    iov[0].iov_base = (void *)data.bytes;
    iov[0].iov_len = data.length;
    int iovcnt = 1;

    struct sctp_sndinfo  send_info;
    memset(&send_info,0x00,sizeof(struct sctp_sndinfo));
    send_info.snd_sid = streamId;
    send_info.snd_flags = 0;
    send_info.snd_ppid = htonl(protocolId);
    send_info.snd_context = 0;
    send_info.snd_assoc_id = *assocptr;

    sp = sctp_sendv(_sock,
                    iov,
                    iovcnt,
                    (struct sockaddr *)remote_sockaddr.bytes,
                    count,
                    &send_info,
                    sizeof(struct sctp_sndinfo),
                    SCTP_SENDV_SNDINFO,
                    flags);
#else

	int timetolive=8000;
	int context=0;

#if defined(ULIBSCTP_CONFIG_DEBUG)
	NSMutableString *s = [[NSMutableString alloc]init];

	[s appendFormat:@"sctp_sendmsg(_sock=%d,\n",_sock];
	[s appendFormat:@"\tdata.bytes=%p\n",(void *)data.bytes];
	[s appendFormat:@"\tdata.length=%ld\n",(long)data.length];
	[s appendFormat:@"\t(struct sockaddr *)remote_sockaddr.bytes=%p\n",remote_sockaddr.bytes];
	[s appendFormat:@"\t(socklen_t)remote_sockaddr.length=%ld\n",(long)remote_sockaddr.length];
	[s appendFormat:@"\tprotocolId=%ld\n",(long)protocolId];
	[s appendFormat:@"\tflags=%ld\n",(long)flags];
    [s appendFormat:@"\tstreamId=%ld\n",(long)streamId];
	[s appendFormat:@"\ttimetolive=%ld\n",(long)timetolive];
	[s appendFormat:@"\tcontext=%ld\n",(long)context];
	[s appendFormat:@"\tassoc=%ld\n",(long)*assocptr];
	[s appendFormat:@"\tremote Addresses: %@\n",[addrs componentsJoinedByString:@","]];
	[s appendFormat:@"\tremote Port: %ld\n",(long)remotePort];
	if(self.logFeed)
	{
		[self.logFeed debugText:s];
	}
	else
	{
		NSLog(@"%@",s);
	}
#endif

    sp = sctp_sendmsg(_sock,
                      (const void *)data.bytes,
                      data.length,
                      (struct sockaddr *)remote_sockaddr.bytes,
                      (socklen_t)remote_sockaddr.length,
                      htonl(protocolId),
                      flags, /* flags */
                      streamId,
                      timetolive, // timetolive,
                      context); // context);

#endif

    if(sp<0)
    {
#if defined(ULIBSCTP_CONFIG_DEBUG)
		NSString *s = [NSString stringWithFormat:@"errno: %d %s",errno, strerror(errno)];
		[self.logFeed debugText:s];
#endif

        err = [UMSocket umerrFromErrno:errno];
    }
    else if(sp==0)
    {
        err = UMSocketError_no_data;
    }

    if(err2)
    {
        *err2 = err;
    }
    return sp;
}



- (UMSocketError) abortToAddress:(NSString *)addr
                            port:(int)remotePort
                           assoc:(uint32_t)assoc
                          stream:(uint16_t)streamId
                        protocol:(u_int32_t)protocolId
{
    UMSocketError err = UMSocketError_no_error;
    ssize_t sp = 0;
    int count = 0;
    NSArray *addrs = @[addr];
    NSData *remote_sockaddr = [UMSocketSCTP sockaddrFromAddresses:addrs port:remotePort count:&count socketFamily:_socketFamily]; /* returns struct sockaddr data in NSData */
    int flags = SCTP_ABORT;

    uint32_t timetolive=8000;
    uint32_t context=0;

#if defined(ULIBSCTP_CONFIG_DEBUG)
    NSLog(@"sctp_sendmsg(_sock=%d,\n\tdata.bytes=NULL\n\tdata.length=0\n\t(struct sockaddr *)remote_sockaddr.bytes=%p\n\t(socklen_t)remote_sockaddr.length=%ld\n\tprotocolId=%ld\n\tflags=%ld\n\tstreamId=%ld\n\ttimetolive=%ld\n\tcontext=%ld\n);\n",
          (int)_sock,
          remote_sockaddr.bytes,
          (long)remote_sockaddr.length,
          (long)protocolId,
          (long)flags, /* flags */
          (long)streamId,
          (long)timetolive, // timetolive,
          (long)context); // context);
#endif

    sp = sctp_sendmsg(_sock,
                      NULL,
                      0,
                      (struct sockaddr *)remote_sockaddr.bytes,
                      (socklen_t)remote_sockaddr.length,
                      htonl(protocolId),
                      flags, /* flags */
                      streamId,
                      timetolive, // timetolive,
                      context); // context);
    if(sp<0)
    {
        int e = errno;
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"errno: %d %s",e, strerror(e));
#endif

        err = [UMSocket umerrFromErrno:e];
    }
    else if(sp==0)
    {
        err = UMSocketError_no_error;
    }
    return err;
}


#define SCTP_RXBUF 10240

- (UMSocketSCTPReceivedPacket *)receiveSCTP
{
    struct sockaddr_in6     remote_address6;
    struct sockaddr_in      remote_address4;
    struct sockaddr *       remote_address_ptr;
    socklen_t               remote_address_len;
    sctp_assoc_t            assoc;

    if(_socketFamily==AF_INET)
    {
        remote_address_ptr = (struct sockaddr *)&remote_address4;
        remote_address_len = sizeof(struct sockaddr_in);
    }
    else
    {
        remote_address_ptr = (struct sockaddr *)&remote_address6;
        remote_address_len = sizeof(struct sockaddr_in6);
    }

    ssize_t                 bytes_read = 0;
    char                    buffer[SCTP_RXBUF+1];
    int                     flags=0;
    uint16_t                streamId;
    uint32_t                protocolId;
    uint32_t                context;

    memset(&buffer[0],0xFA,sizeof(buffer));
    memset(remote_address_ptr,0x00,sizeof(remote_address_len));

    UMSocketSCTPReceivedPacket *rx = [[UMSocketSCTPReceivedPacket alloc]init];

#if defined __APPLE__
// we want to test unix behaviour here... so we ignore this for now
//define ULIBSCTP_SCTP_RECVV_SUPPORTED 1
#undef ULIBSCTP_SCTP_RECVV_SUPPORTED
#endif

#if defined(ULIBSCTP_SCTP_RECVV_SUPPORTED)

    struct sctp_rcvinfo     rinfo;
    socklen_t               rinfo_len;
    struct iovec            iov[1];
    int                     iovcnt = 1;
    unsigned int            infoType;

    memset(&rinfo,0x00,sizeof(struct sctp_rcvinfo));

    iov[0].iov_base = &buffer;
    iov[0].iov_len = SCTP_RXBUF;
    rinfo_len = sizeof(struct sctp_rcvinfo);
    infoType = SCTP_RECVV_RCVINFO;
    bytes_read = sctp_recvv(_sock,
                            iov,
                            iovcnt,
                            remote_address_ptr,
                            &remote_address_len,
                            &rinfo,
                            &rinfo_len,
                            &infoType,
                            &flags);

    streamId = rinfo.rcv_sid;
    protocolId = ntohl(rinfo.rcv_ppid);
    context = ntohl(rinfo.rcv_context);
    assoc  = rinfo.rcv_assoc_id;
#else

    struct sctp_sndrcvinfo sinfo;
#if defined(SCTP_FUTURE_ASSOC)
    sinfo.sinfo_assoc_id = SCTP_FUTURE_ASSOC;
#endif
    memset(&sinfo,0xFF,sizeof(struct sctp_sndrcvinfo));
    bytes_read = sctp_recvmsg(_sock,
                         &buffer,
                         SCTP_RXBUF,
                         remote_address_ptr,
                         &remote_address_len,
                         &sinfo,
                         &flags);

    streamId = sinfo.sinfo_stream;
    protocolId = ntohl(sinfo.sinfo_ppid);
    context = sinfo.sinfo_context;
    assoc = sinfo.sinfo_assoc_id;
#endif

    rx.socket = @(_sock);

    if(bytes_read <= 0)
    {
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"errno %d %s",errno,strerror(errno));
#endif
        rx.err = [UMSocket umerrFromErrno:errno];
    }
    else
    {
        rx.remoteAddress = [UMSocket addressOfSockAddr:remote_address_ptr];
        rx.remotePort = [UMSocket portOfSockAddr:remote_address_ptr];
        rx.data = [NSData dataWithBytes:&buffer length:bytes_read];
        rx.flags = flags;
		if(_msg_notification_mask==0)
		{
			_msg_notification_mask = MSG_NOTIFICATION;
		}

        if(flags & _msg_notification_mask)
        {
            rx.isNotification = YES;
        }
        rx.streamId =streamId;
        rx.protocolId = protocolId;
        rx.context = context;
        rx.assocId = @((uint32_t)assoc);
    }
    return rx;
}

- (UMSocketError)close
{
    _dataDelegate = NULL;
    _notificationDelegate = NULL;
    self.status = UMSOCKET_STATUS_OFF;
    return [super close];
}


- (UMSocketError) dataIsAvailableSCTP:(int)timeoutInMs
                            dataAvail:(int *)hasData
                               hangup:(int *)hasHup
{
    UMSocketError returnValue = UMSocketError_no_data;
    struct pollfd pollfds[1];
    int ret1;
    int ret2;
    int eno = 0;

    int events = POLLIN | POLLPRI | POLLERR | POLLHUP | POLLNVAL;
    
#ifdef POLLRDBAND
    events |= POLLRDBAND;
#endif

#ifdef POLLRDHUP
    events |= POLLRDHUP;
#endif
    
    memset(pollfds,0,sizeof(pollfds));
    pollfds[0].fd = _sock;
    pollfds[0].events = events;
    
    //    UMAssert(timeoutInMs>0,@"timeout should be larger than 0");
    UMAssert(timeoutInMs<200000,@"timeout should be smaller than 20seconds");
    
#if defined(ULIBSCTP_CONFIG_DEBUG)
    NSLog(@"calling poll (timeout =%dms,socket=%d)",timeoutInMs,_sock);
#endif

    [_controlLock lock];
    ret1 = poll(pollfds, 1, timeoutInMs);
    [_controlLock unlock];


    if (ret1 < 0)
    {
        eno = errno;
        if((eno==EINPROGRESS) || (eno == EINTR) || (eno==EAGAIN))
        {
            returnValue = UMSocketError_no_data;
        }
        else
        {
            returnValue = [UMSocket umerrFromErrno:eno];
        }
    }
    else if (ret1 == 0)
    {
        returnValue = UMSocketError_no_data;
    }
    else /* ret1 > 0 */
    {
        /* we have some event to handle. */
        ret2 = pollfds[0].revents;
#if defined(ULIBSCTP_CONFIG_DEBUG)
        NSLog(@"pollfds[0].revents = %d",ret2);
#endif
        if(ret2 & POLLERR)
        {
            returnValue = [self getSocketError];
        }

        if(ret2 & POLLHUP)
        {
            *hasHup = 1;
        }
        
#ifdef POLLRDHUP
        if(ret2 & POLLRDHUP)
        {
            *hasHup = 1;
        }
#endif
        if(ret2 & POLLNVAL)
        {
            returnValue = UMSocketError_file_descriptor_not_open;
        }
#ifdef POLLRDBAND
        if(ret2 & POLLRDBAND)
        {
            *hasData = 1;
        }
#endif
        /* There is data to read.*/
        if(ret2 & (POLLIN | POLLPRI))
        {
            *hasData = 1;
        }
        if(*hasData)
        {
            if(returnValue == UMSocketError_no_data)
            {
                returnValue = UMSocketError_has_data;
                if(*hasHup)
                {
                    returnValue = UMSocketError_has_data_and_hup;
                }
            }
        }
    }
    return returnValue;
}

- (UMSocketError) getSocketError
{
    int eno = 0;
    socklen_t len = sizeof(int);
    getsockopt(_sock, SOL_SOCKET, SO_ERROR, &eno, &len);
    return  [UMSocket umerrFromErrno:eno];
}


- (UMSocketError) setReusePort
{
#if defined(SCTP_REUSE_PORT)

    int flags = 1;
    int err = setsockopt(_sock, IPPROTO_SCTP, SCTP_REUSE_PORT, (char *)&flags, sizeof(flags));
    if(err !=0)
    {
        return [UMSocket umerrFromErrno:errno];
    }
    return    UMSocketError_no_error;
#else
    return UMSocketError_not_supported_operation;
#endif
}

- (UMSocketError) setNoDelay
{
#if defined(SCTP_NODELAY)
    int flags = 1;
    int err = setsockopt(_sock, IPPROTO_SCTP, SCTP_NODELAY, (char *)&flags, sizeof(flags));
    if(err !=0)
    {
        return [UMSocket umerrFromErrno:errno];
    }
    return    UMSocketError_no_error;
#else
    return UMSocketError_not_supported_operation
#endif
}


- (UMSocketError) setInitParams
{
#if defined(SCTP_INITMSG)
    struct sctp_initmsg  params;
    memset((void *)&params,0x00, sizeof(struct sctp_initmsg));
    socklen_t len = sizeof(params);

    int err = getsockopt(_sock, IPPROTO_SCTP, SCTP_INITMSG, &params, &len);
    if(err==0)
    {
        if(_maxInStreams>0)
        {
            params.sinit_max_instreams = _maxInStreams;
        }
        if(_numOStreams>0)
        {
            params.sinit_num_ostreams = _numOStreams;
        }
        if(_maxInitAttempts>0)
        {
            params.sinit_max_attempts = _maxInitAttempts;
        }
        if(_initTimeout>0)
        {
            params.sinit_max_init_timeo = _initTimeout;
        }
        err = setsockopt(_sock, IPPROTO_SCTP, SCTP_INITMSG, &params, len);
    }
    if(err !=0)
    {
        return [UMSocket umerrFromErrno:errno];
    }
    return    UMSocketError_no_error;
#else
    return UMSocketError_not_supported_operation
#endif
}


- (UMSocketError) listen: (int) backlog
{
    [self updateName];
    int err;
    self.status = UMSOCKET_STATUS_LISTENING;

    [self reportStatus:@"caling listen()"];
    if (self.isListening == 1)
    {
        [self reportStatus:@"- already listening"];
        return UMSocketError_already_listening;
    }
    self.isListening = 0;
    
    [_controlLock lock];
    err = listen(_sock,backlog);
    [_controlLock unlock];

    direction = direction | UMSOCKET_DIRECTION_INBOUND;
    if(err)
    {
        int eno = errno;
        return [UMSocket umerrFromErrno:eno];
    }
    self.isListening = 1;
#if defined(SCTP_LISTEN_FIX)
    int flag=1;
    [_controlLock lock];
    setsockopt(_sock,IPPROTO_SCTP,SCTP_LISTEN_FIX,&flag,sizeof(flag));
    [_controlLock unlock];
#endif
    [self reportStatus:@"isListening=1"];
    return UMSocketError_no_error;
}


- (NSArray *)getRemoteIpAddressesForAssoc:(uint32_t)assoc
{
    NSMutableArray *arr = [[NSMutableArray alloc]init];
    struct sockaddr *addrs=NULL;
    int e = sctp_getpaddrs(_sock, (sctp_assoc_t)assoc, &addrs);
    if(e<0)
    {
        if(addrs)
        {
            sctp_freepaddrs(addrs);
        }
        return NULL;
    }
    for(int i=0;i<e;i++)
    {
        NSString *a = [UMSocket addressOfSockAddr:&addrs[i]];
        if(a)
        {
            [arr addObject:a];
        }
    }
    return arr;
}

-(int)bindx:(struct sockaddr *)localAddress
{
    int err = sctp_bindx(_sock, localAddress,1,SCTP_BINDX_ADD_ADDR);
    return err;
}


@end
