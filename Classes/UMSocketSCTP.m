//
//  UMSocketSCTP.m
//  ulibsctp
//
//  Created by Andreas Fink on 14.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//


#import "UMSocketSCTP.h"
#import "UMSocketSCTPListener.h"

#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/poll.h>
#include <arpa/inet.h>
#include <string.h>

#ifdef __APPLE__
#import <sctp/sctp.h>
#include <sys/utsname.h>

#define MSG_NOTIFICATION_MAVERICKS 0x40000        /* notification message */
#define MSG_NOTIFICATION_YOSEMITE  0x80000        /* notification message */
//#define ULIBSCTP_SCTP_SENDV_SUPPORTED 1
//#define ULIBSCTP_SCTP_RECVV_SUPPORTED 1

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
    _sock = -1;
    switch(type)
    {
        case UMSOCKET_TYPE_SCTP4ONLY:
            _socketFamily=AF_INET;
            _socketType = SOCK_SEQPACKET;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP6ONLY:
            _socketFamily=AF_INET6;
            _socketType = SOCK_SEQPACKET;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP:
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
}

- (void)dealloc
{
    if(_local_addresses)
    {
        free(_local_addresses);
        _local_addresses=NULL;
    }
}




- (void)prepareLocalAddresses
{
    if(_local_addresses_prepared)
    {
        return;
    }
    struct sockaddr_in6 *local_addresses6;
    struct sockaddr_in *local_addresses4;
    
    int count = (int)_requestedLocalAddresses.count;
    
    int i;
    int j=0;
    if(_socketFamily==AF_INET6)
    {
        local_addresses6 = calloc(count,sizeof(struct sockaddr_in6));
        for(i=0;i<count;i++)
        {
            NSString *address = [_requestedLocalAddresses objectAtIndex:i];
            NSString *address2 = [UMSocket deunifyIp:address];
            if(address2.length>0)
            {
                address = address2;
            }
            if([address isIPv4])
            {
                /* we have a IPV6 socket but the local addres is in IPV4 format so we must use the IPv6 representation of it */
                address =[NSString stringWithFormat:@"::ffff:%@",address];
            }
            int result = inet_pton(AF_INET6,address.UTF8String, &local_addresses6[j].sin6_addr);
            if(result==1)
            {
#ifdef HAVE_SOCKADDR_SIN_LEN
                local_addresses6[i].sin6_len = sizeof(struct sockaddr_in6);
#endif
                local_addresses6[j].sin6_family = AF_INET6;
                local_addresses6[j].sin6_port = htons(requestedLocalPort);
                j++;
            }
            else
            {
                NSLog(@"%@ is not a valid IP address. skipped ",address);
            }
        }
        _local_addresses_count = j;
        if(_local_addresses)
        {
            free(_local_addresses);
            _local_addresses = NULL;
        }
        if(j==0)
        {
            NSLog(@"no valid local IP addresses found");
            free(local_addresses6);
        }
        else
        {
            if(j<i)
            {
                local_addresses6 = realloc(local_addresses6,sizeof(struct sockaddr_in6)*j);
            }
            _local_addresses = (struct sockaddr *)local_addresses6;
            _local_addresses_prepared=YES;
        }
    }
    else if(_socketFamily==AF_INET)
    {
        local_addresses4 = calloc(count,sizeof(struct sockaddr_in));
        for(int i=0;i<count;i++)
        {
            NSString *address = [_requestedRemoteAddresses objectAtIndex:i];
            NSString *address2 = [UMSocket deunifyIp:address];
            if(address2.length>0)
            {
                address = address2;
            }
            int result = inet_pton(AF_INET,address.UTF8String, &local_addresses4[j].sin_addr);
            if(result==1)
            {
#ifdef HAVE_SOCKADDR_SIN_LEN
                local_addresses4[i].sin_len = sizeof(struct sockaddr_in);
#endif
                local_addresses4[j].sin_family = AF_INET;
                local_addresses4[j].sin_port = htons(requestedRemotePort);
                j++;
            }
            else
            {
                NSLog(@"'%@' is not a valid IP address. skipped ",address);
            }
        }
        _local_addresses_count = j;
        if(j==0)
        {
            NSLog(@"no valid local IPv4 addresses found");
            free(local_addresses4);
        }
        else
        {
            if(j<count)
            {
                local_addresses4 = realloc(local_addresses4,sizeof(struct sockaddr_in)*j);
            }
            _local_addresses = (struct sockaddr *)local_addresses4;
            _local_addresses_prepared=YES;
        }
    }
}

- (UMSocketError) bind
{
    NSMutableArray *useable_local_addr = [[NSMutableArray alloc]init];

    if(!_local_addresses_prepared)
    {
        [self prepareLocalAddresses];
    }
    /* at this point usable_addresses contains strings which are in _socketFamily specific formats */
    /* invalid IP's have been remvoed */
    int usable_ips = -1;
    
    for(int i=0;i<_local_addresses_count;i++)
    {
        NSString *addr = [UMSocket addressOfSockAddr:&_local_addresses[i]];
        int port = [UMSocket portOfSockAddr:&_local_addresses[i]];
        if(usable_ips == -1)
        {
#if (ULIBSCTP_CONFIG==Debug)
            NSLog(@"calling bind for '%@:%d' on socket %d",addr,port,_sock);
#endif
            int err;
            if(_socketFamily == AF_INET6)
            {
                err = bind(_sock, &_local_addresses[i],sizeof(struct sockaddr_in6));
            }
            else
            {
                err = bind(_sock, &_local_addresses[i],sizeof(struct sockaddr_in));
            }
            if(err==0)
            {
#if (ULIBSCTP_CONFIG==Debug)
                NSLog(@" bind succeeds for %@",addr);
#endif
                usable_ips = 1;
                [useable_local_addr addObject:addr];
            }
            else
            {
                NSLog(@" bind returns error %d %s",errno,strerror(errno));
            }
        }
        else
        {
#if (ULIBSCTP_CONFIG==Debug)
            NSLog(@"calling sctp_bindx for '%@'",addr);
#endif
            int err = sctp_bindx(_sock, &_local_addresses[i],1,SCTP_BINDX_ADD_ADDR);
            if(err==0)
            {
#if (ULIBSCTP_CONFIG==Debug)
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
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"bind(SCTP): usable_ips=%d",usable_ips);
#endif
        return UMSocketError_address_not_available;
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
    
    self.status = SCTP_STATUS_OOS;


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


- (UMSocketError) enableFutureAssoc
{
#if defined(SCTP_FUTURE_ASSOC) && defined(SCTP_ADAPTATION_INDICATION)
    struct sctp_event event;

    /* Enable the events of interest. */
    memset(&event, 0, sizeof(event));
    event.se_assoc_id = SCTP_FUTURE_ASSOC;
    event.se_on = 1;
    event.se_type = SCTP_ADAPTATION_INDICATION;
    if (setsockopt(_sock, IPPROTO_SCTP, SCTP_EVENT, &event, sizeof(event)) < 0)
    {
        return [UMSocket umerrFromErrno:errno];
    }
#endif
    return UMSocketError_no_error;

}

+ (NSData *)sockaddrFromAddresses:(NSArray *)theAddrs
                             port:(int)thePort
                            count:(int *)count_out /* returns struct sockaddr data in NSData */
                     socketFamily:(int)socketFamily
{
    struct sockaddr_in6 *addresses6;
    struct sockaddr_in  *addresses4;
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
                addresses6[i].sin6_len = sizeof(struct sockaddr_in6);
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
            NSLog(@"no valid local IP addresses found");
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
                addresses4[i].sin_len = sizeof(struct sockaddr_in);
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
            NSLog(@"no valid local IPv4 addresses found");
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

- (UMSocketError) connectToAddresses:(NSArray *)addrs
                                port:(int)remotePort
                               assoc:(sctp_assoc_t *)assocptr
{

    int count = 0;
    NSData *remote_sockaddr = [UMSocketSCTP sockaddrFromAddresses:addrs port:remotePort count:&count socketFamily:_socketFamily]; /* returns struct sockaddr data in NSData */

    /**********************/
    /* CONNECTX           */
    /**********************/
    UMSocketError returnValue = UMSocketError_no_error;

    if(count<1)
    {
        returnValue = UMSocketError_address_not_available;
    }
    else
    {
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"calling sctp_connectx (%@)", [addrs componentsJoinedByString:@" "]);
#endif
        memset(assocptr,0,sizeof(sctp_assoc_t));
        int err =  sctp_connectx(_sock,(struct sockaddr *)remote_sockaddr.bytes,count,assocptr);
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"sctp_connectx: returns %d. errno = %d %s assoc=%lu",err,errno,strerror(errno),(unsigned long)*assocptr);
#endif
        if (err < 0)
        {
            returnValue = [UMSocket umerrFromErrno:errno];
        }
        else
        {
            returnValue = UMSocketError_no_error;
        }
    }
    return returnValue;
}

- (UMSocketSCTP *) acceptSCTP:(UMSocketError *)ret
{
    [_controlLock lock];
    @try
    {
        int           newsock = -1;
        UMSocketSCTP  *newcon =NULL;
        NSString *remoteAddress=@"";
        in_port_t remotePort=0;
        if( type == UMSOCKET_TYPE_SCTP4ONLY)
        {
            struct    sockaddr_in sa4;
            socklen_t slen4 = sizeof(sa4);
            newsock = accept(_sock,(struct sockaddr *)&sa4,&slen4);
            if(newsock >=0)
            {
                char hbuf[NI_MAXHOST];
                char sbuf[NI_MAXSERV];
                if (getnameinfo((struct sockaddr *)&sa4, slen4, hbuf, sizeof(hbuf), sbuf,
                                sizeof(sbuf), NI_NUMERICHOST | NI_NUMERICSERV))
                {
                    remoteAddress = @"ipv4:0.0.0.0";
                    remotePort = sa4.sin_port;
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
            newsock = accept(_sock,(struct sockaddr *)&sa6,&slen6);
            if(newsock >= 0)
            {
                char hbuf[NI_MAXHOST], sbuf[NI_MAXSERV];
                if (getnameinfo((struct sockaddr *)&sa6, slen6, hbuf, sizeof(hbuf), sbuf,
                                sizeof(sbuf), NI_NUMERICHOST | NI_NUMERICSERV))
                {
                    remoteAddress = @"ipv6:[::]";
                    remotePort = sa6.sin6_port;
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
            newcon.direction =  direction;
            newcon.status=status;
            newcon.localHost = localHost;
            newcon.remoteHost = remoteHost;
            newcon.requestedLocalAddresses = _requestedLocalAddresses;
            newcon.requestedLocalPort=requestedLocalPort;
            newcon.requestedRemoteAddresses = _requestedRemoteAddresses;
            newcon.requestedRemotePort=requestedRemotePort;
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
            [newcon updateName];
            newcon.objectStatisticsName = @"UMSocket(accept)";
            [self reportStatus:@"accept () successful"];
            /* TODO: start SSL if required here */
            *ret = UMSocketError_no_error;
            return newcon;
        }
        *ret = [UMSocket umerrFromErrno:errno];
        return nil;
    }
    @finally
    {
        [_controlLock unlock];
    }
}


- (ssize_t) sendToAddresses:(NSArray *)addrs
                       port:(int)remotePort
                      assoc:(sctp_assoc_t *)assocptr
                       data:(NSData *)data
                     stream:(uint16_t)streamId
                   protocol:(u_int32_t)protocolId
                      error:(UMSocketError *)err2
{
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

    if(*assocptr==0)
    {
        err = [self connectToAddresses:addrs
                                  port:remotePort
                                 assoc:assocptr];
        if((err != UMSocketError_no_error) && (err != UMSocketError_in_progress))
        {
            if(err2)
            {
                *err2 = err;
            }
            return -1;
        }
    }
    if (*assocptr==0)
    {
        if(err2)
        {
            *err2 = UMSocketError_address_not_available;
        }
        return -1;
    }


#if defined(ULIBSCTP_SCTP_SENDV_SUPPORTED)

    int count = 0;
    NSData *remote_sockaddr = [UMSocketSCTP sockaddrFromAddresses:addrs port:remotePort count:&count socketFamily:_socketFamily]; /* returns struct sockaddr data in NSData */

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
    int flags = 0;
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

    int count=0;
    NSData *remote_sockaddr = [UMSocketSCTP sockaddrFromAddresses:addrs port:remotePort count:&count socketFamily:_socketFamily]; /* returns struct sockaddr data in NSData */

    struct sctp_sndrcvinfo sinfo;
    memset(&sinfo,0x00,sizeof(struct sctp_sndrcvinfo));

    sinfo.sinfo_stream = streamId;
    sinfo.sinfo_flags = 0;
    sinfo.sinfo_ppid = htonl(protocolId);
    sinfo.sinfo_context = 0;
    sinfo.sinfo_timetolive = 2000;
    sinfo.sinfo_assoc_id = *assocptr;
    int flags=0;
    /*
    sp = sctp_send(_sock,
                   (const void *)data.bytes,
                   data.length,
                   &sinfo,
                   flags);
*/
    sp = sctp_sendmsg(_sock,
                      (const void *)data.bytes,
                      data.length,
                      (struct sockaddr *)remote_sockaddr.bytes,
                      (socklen_t)remote_sockaddr.length,
                      htonl(protocolId),
                      0, /* flags */
                      streamId,
                      2000, // timetolive,
                      0); // context);

#endif

    if(sp<0)
    {
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
//define ULIBSCTP_SCTP_RECVV_SUPPORTED 1
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
    memset(&sinfo,0x00,sizeof(struct sctp_sndrcvinfo));
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
    if(!(flags & MSG_NOTIFICATION))
    {
        NSLog(@"Data for protocolId %d received",protocolId);
    }
#endif

    if(bytes_read <= 0)
    {
        NSLog(@"errno %d %s",errno,strerror(errno));
        rx.err = [UMSocket umerrFromErrno:errno];
    }
    else
    {
        rx.remoteAddress = [UMSocket addressOfSockAddr:remote_address_ptr];
        rx.remotePort = [UMSocket portOfSockAddr:remote_address_ptr];
        rx.data = [NSData dataWithBytes:&buffer length:bytes_read];
        rx.flags = flags;
        if(flags & _msg_notification_mask)
        {
            rx.isNotification = YES;
        }
        rx.streamId =streamId;
        rx.protocolId = protocolId;
        rx.context = context;
        rx.assocId = @(assoc);
    }
    return rx;
}

- (UMSocketError)close
{
    _dataDelegate = NULL;
    _notificationDelegate = NULL;
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
    
    [_controlLock lock];
    memset(pollfds,0,sizeof(pollfds));
    pollfds[0].fd = _sock;
    pollfds[0].events = events;
    
    //    UMAssert(timeoutInMs>0,@"timeout should be larger than 0");
    UMAssert(timeoutInMs<200000,@"timeout should be smaller than 20seconds");
    
#if (ULIBSCTP_CONFIG==Debug)
    NSLog(@"calling poll (timeout =%dms,socket=%d)",timeoutInMs,_sock);
#endif

    ret1 = poll(pollfds, 1, timeoutInMs);

#if (ULIBSCTP_CONFIG==Debug)
    NSLog(@" poll returns %d (%d:%s)",ret1,errno,strerror(errno));
#endif

    [_controlLock unlock];

    if (ret1 < 0)
    {
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"poll: %d %s",errno,strerror(errno));
#endif
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
#if (ULIBSCTP_CONFIG==Debug)
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


- (UMSocketError) listen: (int) backlog
{
    [self updateName];
    [_controlLock lock];
    @try
    {
        int err;
        
        [self reportStatus:@"caling listen()"];
        if (self.isListening == 1)
        {
            [self reportStatus:@"- already listening"];
            return UMSocketError_already_listening;
        }
        self.isListening = 0;
        
        err = listen(_sock,backlog);
        
        direction = direction | UMSOCKET_DIRECTION_INBOUND;
        if(err)
        {
            int eno = errno;
            return [UMSocket umerrFromErrno:eno];
        }
        self.isListening = 1;
#if defined(SCTP_LISTEN_FIX)
        int flag=1;
        setsockopt(_sock,IPPROTO_SCTP,SCTP_LISTEN_FIX,&flag,sizeof(flag));
#endif
        [self reportStatus:@"isListening=1"];
        return UMSocketError_no_error;
    }
    @finally
    {
        [_controlLock unlock];
    }
}


@end
