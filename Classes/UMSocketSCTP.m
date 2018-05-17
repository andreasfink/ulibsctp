//
//  UMSocketSCTP.m
//  ulibsctp
//
//  Created by Andreas Fink on 14.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//
#import "UMSocketSCTP.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/poll.h>
#include <arpa/inet.h>

#ifdef __APPLE__
#import <sctp/sctp.h>
#include <sys/utsname.h>

#define MSG_NOTIFICATION_MAVERICKS 0x40000        /* notification message */
#define MSG_NOTIFICATION_YOSEMITE  0x80000        /* notification message */
#else
#include "netinet/sctp.h"
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

@implementation UMSocketSCTP

- (void)initNetworkSocket
{
    _sock = -1;
    switch(type)
    {
        case UMSOCKET_TYPE_SCTP4ONLY:
            _socketFamily=AF_INET;
            _socketType = SOCK_STREAM;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP6ONLY:
            _socketFamily=AF_INET6;
            _socketType = SOCK_STREAM;
            _socketProto = IPPROTO_SCTP;
            _sock = socket(_socketFamily,_socketType, _socketProto);
            TRACK_FILE_SOCKET(_sock,@"sctp");
            break;
        case UMSOCKET_TYPE_SCTP:
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


- (UMSocketError) bind;
{
    int usable_ips = -1;
    NSMutableArray *usable_addresses = [[NSMutableArray alloc]init];

#if (ULIBSCTP_CONFIG==Debug)
    NSLog(@"bind (SCTP): _requestedLocalAddresses = %@",_requestedLocalAddresses);
#endif
    
    for(NSString *a in _requestedLocalAddresses)
    {
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"bind (SCTP): parsing %@",a);
#endif

        NSString *address = [UMSocket deunifyIp:a];
        if(address.length==0)
        {
            address = a;
        }
        if([address isIPv4])
        {
            if(_socketFamily==AF_INET6)
            {
                address = [NSString stringWithFormat:@"::ffff:%@",address];
            }
            [usable_addresses addObject:address];
        }
        else if([address isIPv6])
        {
            if(_socketFamily==AF_INET6)
            {
                [usable_addresses addObject:address];
            }
            else
            {
                NSLog(@"IPv4 only socket doesnt support IPv6 address %@",address);
            }
        }
        else
        {
            NSLog(@"Can not interpret address '%@'. Skipping it",address);
        }
    }
    /* at this point usable_addresses contains strings which are in _socketFamily specific formats */
    /* invalid IP's have been remvoed */
    
#if (ULIBSCTP_CONFIG==Debug)
    NSLog(@"bind (SCTP): usable_addresses = %@",usable_addresses);
#endif
    
    NSMutableArray *useAddresses = [[NSMutableArray alloc]init];
    if(_socketFamily==AF_INET6)
    {
        for(NSString *address in usable_addresses)
        {
            struct sockaddr_in6        local_addr6;
            memset(&local_addr6,0x00,sizeof(local_addr6));
            
            local_addr6.sin6_family = AF_INET6;
#ifdef HAVE_SOCKADDR_SIN_LEN
            local_addr6.sin6_len         = sizeof(struct sockaddr_in6);
#endif
            local_addr6.sin6_port = htons(self.requestedLocalPort);
            
            int result = inet_pton(AF_INET6,address.UTF8String, &local_addr6.sin6_addr);
            if(result==1)
            {
                if(usable_ips == -1)
                {
                    /* first IP */
#if (ULIBSCTP_CONFIG==Debug)
                    NSLog(@"calling bind for '%@'",address);
#endif
                    int err = bind(_sock, (struct sockaddr *)&local_addr6,sizeof(local_addr6));
                    if(err==0)
                    {
#if (ULIBSCTP_CONFIG==Debug)
                        NSLog(@" bind succeeds");
#endif
                        usable_ips = 1;
                        [useAddresses addObject:address];
                    }
                    else
                    {
                        NSLog(@" bind returns error %d %s",errno,strerror(errno));
                    }
                }
                else
                {
#if (ULIBSCTP_CONFIG==Debug)
                    NSLog(@"calling sctp_bindx for '%@'",address);
#endif

                    int err = sctp_bindx(_sock, (struct sockaddr *)&local_addr6,1,SCTP_BINDX_ADD_ADDR);
                    if(err==0)
                    {
#if (ULIBSCTP_CONFIG==Debug)
                        NSLog(@" sctp_bindx succeeds");
#endif

                        usable_ips++;
                        [useAddresses addObject:address];
                    }
                    else
                    {
                        NSLog(@" sctp_bindx returns error %d %s",errno,strerror(errno));
                    }
                }
            }
        }
    }
    else if(_socketFamily==AF_INET)
    {
        /* IPv4 only socket */
        int usable_ips = -1;
        for(NSString *address in usable_addresses)
        {
            struct sockaddr_in  local_addr4;
            memset(&local_addr4,0x00,sizeof(local_addr4));
            
            local_addr4.sin_family = AF_INET;
#ifdef HAVE_SOCKADDR_SIN_LEN
            local_addr4.sin_len         = sizeof(struct sockaddr_in);
#endif
            local_addr4.sin_port = htons(self.requestedLocalPort);
            
            int result = inet_pton(AF_INET,address.UTF8String, &local_addr4.sin_addr);
            if(result==1)
            {
                if(usable_ips == -1)
                {
                    /* first IP */
                    
                    int err = bind(_sock, (struct sockaddr *)&local_addr4,sizeof(local_addr4));
                    if(err==0)
                    {
                        usable_ips = 1;
                        [useAddresses addObject:address];
#if (ULIBSCTP_CONFIG==Debug)
                        NSLog(@" bind succeeds");
#endif

                    }
                    else
                    {
                        NSLog(@" bind returns error %d %s",errno,strerror(errno));
                    }
                }
                else
                {
                    int err = sctp_bindx(_sock, (struct sockaddr *)&local_addr4,1,SCTP_BINDX_ADD_ADDR);
                    if(err==0)
                    {
                        usable_ips++;
                        [useAddresses addObject:address];
#if (ULIBSCTP_CONFIG==Debug)
                        NSLog(@" sctp_bindx succeeds");
#endif
                    }
                    else
                    {
                        NSLog(@" sctp_bindx returns error %d %s",errno,strerror(errno));
                    }
                }
            }
        }
    }
    else
    {
        return UMSocketError_address_not_valid_for_socket_family;
    }
        
    if(usable_ips <= 0)
    {
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"bind(SCTP): usable_ips=%d",usable_ips);
#endif
        return UMSocketError_address_not_available;
    }
    _connectedLocalAddresses = useAddresses;
    return UMSocketError_no_error;
}

- (UMSocketError) enableEvents
{
    struct sctp_event_subscribe event;
    
    /**********************/
    /* ENABLING EVENTS    */
    /**********************/
    
    self.status = SCTP_STATUS_OOS;


    bzero((void *)&event, sizeof(struct sctp_event_subscribe));
    event.sctp_data_io_event            = 1;
    event.sctp_association_event        = 1;
    event.sctp_address_event            = 1;
    event.sctp_send_failure_event       = 1;
    event.sctp_peer_error_event         = 1;
    event.sctp_shutdown_event           = 1;
    event.sctp_partial_delivery_event   = 1;
    event.sctp_adaptation_layer_event   = 1;
    event.sctp_authentication_event     = 1;
#ifndef LINUX
    event.sctp_stream_reset_events      = 1;
#endif
    if(setsockopt(_sock, IPPROTO_SCTP, SCTP_EVENTS, &event, sizeof(event)) != 0)
    {
        /* FIXME: use errno for proper return */
        return UMSocketError_not_supported_operation;
    }
    return UMSocketError_no_error;

}

- (UMSocketError) connectSCTP
{
    /**********************/
    /* CONNECTX           */
    /**********************/
    int i;
    int remote_addresses_count = (int)_requestedRemoteAddresses.count;
    if(remote_addresses_count == 0)
    {
        return UMSocketError_address_not_available;
    }
#if (ULIBSCTP_CONFIG==Debug)
    NSLog(@"ConnectSCTP: _requestedRemoteAddresses = %@",_requestedRemoteAddresses);
#endif
    sctp_assoc_t assoc;
    memset(&assoc,0x00,sizeof(assoc));
    
    if(_socketFamily==AF_INET6)
    {
        struct sockaddr_in6 *remote_addresses6 = malloc(sizeof(struct sockaddr_in6) * remote_addresses_count);
        memset(remote_addresses6,0x00,sizeof(struct sockaddr_in6) * remote_addresses_count);
        int j=0;
        for(i=0;i<remote_addresses_count;i++)
        {
            struct sockaddr_in6 sa6;
            memset(&sa6,0x00,sizeof(sa6));

            NSString *address = [_requestedRemoteAddresses objectAtIndex:i];
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
            struct in6_addr addr6;
            int result = inet_pton(AF_INET6,address.UTF8String, &remote_addresses6[j].sin6_addr);
            if(result==1)
            {
#ifdef HAVE_SOCKADDR_SIN_LEN
                remote_addresses6[i].sin6_len = sizeof(struct sockaddr_in6);
#endif
                remote_addresses6[j].sin6_family = AF_INET6;
                remote_addresses6[j].sin6_port = htons(requestedRemotePort);
                j++;
            }
            else
            {
                NSLog(@"%@ is not a valid IP address. skipped ",address);
            }
        }
        if(j==0)
        {
            NSLog(@"no valid IPs specified");
            return UMSocketError_address_not_available;
        }
        [self switchToBlocking];
        int err =  sctp_connectx(_sock,(struct sockaddr *)&remote_addresses6[0],j,&assoc);

        free(remote_addresses6);
        UMSocketError result = UMSocketError_no_error;
        if (err < 0)
        {
            result = [UMSocket umerrFromErrno:errno];
        }
        [self switchToNonBlocking];
        return result;
    }
    else if(_socketFamily==AF_INET)
    {
        struct sockaddr_in *remote_addresses4 = malloc(sizeof(struct sockaddr_in) * remote_addresses_count);
        memset(remote_addresses4,0x00,sizeof(struct sockaddr_in) * remote_addresses_count);
        int j=0;
        for(i=0;i<remote_addresses_count;i++)
        {
            struct sockaddr_in sa4;
            memset(&sa4,0x00,sizeof(sa4));
            
            NSString *address = [_requestedRemoteAddresses objectAtIndex:i];
            NSString *address2 = [UMSocket deunifyIp:address];
            if(address2.length>0)
            {
                address = address2;
            }

            struct in_addr addr4;
            int result = inet_pton(AF_INET,address.UTF8String, &addr4);
            if(result==1)
            {
#ifdef HAVE_SOCKADDR_SIN_LEN
                remote_addresses4[i].sin_len = sizeof(struct sockaddr_in);
#endif
                remote_addresses4[j].sin_family = AF_INET;
                remote_addresses4[j].sin_addr = addr4;
                j++;
            }
            else
            {
                NSLog(@"'%@' is not a valid IP address. skipped ",address);
            }
        }
        if(j==0)
        {
            NSLog(@"no valid IPs specified");
            return UMSocketError_address_not_available;
        }
        int err =  sctp_connectx(_sock,(struct sockaddr *)&remote_addresses4[0],j,&assoc);
        free(remote_addresses4);
        if (err < 0)
        {
            return [UMSocket umerrFromErrno:errno];
        }
        return UMSocketError_no_error;
    }
    else
    {
        return UMSocketError_address_not_valid_for_socket_family;
    }
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

- (ssize_t)sendSCTP:(NSData *)data
             stream:(uint16_t)streamId
           protocol:(u_int32_t)protocolId
              error:(UMSocketError *)err
{
    if(data == NULL)
    {
        return UMSocketError_no_data;
    }
    ssize_t sp = sctp_sendmsg(
                                        _sock,                              /* file descriptor */
                                        (const void *)data.bytes,           /* data pointer */
                                        (size_t) data.length,               /* data length */
                                        NULL,                               /* const struct sockaddr *to */
                                        0,                                  /* socklen_t tolen */
                                        (u_int32_t)    htonl(protocolId),   /* protocol Id */
                                        (u_int32_t)    0,                   /* uint32_t flags */
                                        streamId, //htons(streamId),        /* uint16_t stream_no */
                                        0,                                  /* uint32_t timetolive, */
                                        0);                                 /* uint32_t context */
    if(err)
    {
        *err = [UMSocket umerrFromErrno:errno];
    }
    return sp;
}

#define SCTP_RXBUF 10240

- (UMSocketError)receiveAndProcessSCTP /* returns number of packets processed and calls the notification and or data delegate */
{
    char                    buffer[SCTP_RXBUF+1];
    int                     flags=0;
    struct sockaddr         source_address;
    struct sctp_sndrcvinfo  sinfo;
    socklen_t               fromlen;
    ssize_t                 bytes_read = 0;

    flags = 0;
    fromlen = sizeof(source_address);
    memset(&source_address,0,sizeof(source_address));
    memset(&sinfo,0,sizeof(sinfo));
    memset(&buffer[0],0xFA,sizeof(buffer));
    
    //    [self logDebug:[NSString stringWithFormat:@"RXT: calling sctp_recvmsg(fd=%d)",link->fd);
    //    debug("sctp",0,"RXT: calling sctp_recvmsg. link=%08lX",(unsigned long)link);
    bytes_read = sctp_recvmsg (_sock, buffer, SCTP_RXBUF, &source_address,&fromlen,&sinfo,&flags);
    //    debug("sctp",0,"RXT: returned from sctp_recvmsg. link=%08lX",(unsigned long)link);
    //    [self logDebug:[NSString stringWithFormat:@"RXT: sctp_recvmsg: bytes read =%ld, errno=%d",(long)bytes_read,(int)errno);
    
#if (ULIBSCTP_CONFIG==Debug)
    NSLog(@"sctp_recvmsg returns bytes_read=%d",(int)bytes_read);
#endif

    if(bytes_read == 0)
    {
        if(errno==ECONNRESET)
        {
#if (ULIBSCTP_CONFIG==Debug)
            NSLog(@"receiveAndProcessSCTP returning UMSocketError_connection_reset");
#endif
            
            return UMSocketError_connection_reset;
        }
    }
    if(bytes_read <= 0)
    {
        /* we are having a non blocking read here */
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"errno=%d %s",errno,strerror(errno));
#endif
        return [UMSocket umerrFromErrno:errno];
    }
    
    /* bytes_read is > 0 here */
    NSData *data = [NSData dataWithBytes:&buffer length:bytes_read];
#if (ULIBSCTP_CONFIG==Debug)
    NSLog(@"Read DATA=%@",[data hexString]);
#endif
    NSLog(@"flags=%u",flags);

    if(flags & _msg_notification_mask)
    {
        return [self.notificationDelegate handleEvent:data
                                                sinfo:&sinfo];
    }
    else
    {
        uint16_t streamId = sinfo.sinfo_stream;
        uint32_t protocolId = ntohl(sinfo.sinfo_ppid);
        
#if (ULIBSCTP_CONFIG==Debug)
        NSLog(@"streamId=%u",streamId);
        NSLog(@"protocolId=%u",protocolId);
        NSLog(@"dataDelegate=%@",self.dataDelegate);
        NSLog(@"data=%@",[data hexString]);
#endif
        
        return [self.dataDelegate sctpReceivedData:data
                                          streamId:streamId
                                        protocolId:protocolId];
    }
    return 1;
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
        if((eno==EINPROGRESS) || (eno == EINTR))
        {
            return UMSocketError_no_data;
        }
        returnValue = [UMSocket umerrFromErrno:eno];
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
            returnValue = UMSocketError_invalid_file_descriptor;
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

@end
