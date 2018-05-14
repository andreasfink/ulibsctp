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

@implementation UMSocketSCTP

- (void)initNetworkSocket
{
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
}

- (UMSocketError) setSctpOptionNoDelay
{
#ifdef SCTP_NODELAY
    char on = 1;
    if(setsockopt(_sock, IPPROTO_SCTP, SCTP_NODELAY, (char *)&on, sizeof(on)))
    {
        /* FIXME: use errno for proper return */
        return UMSocketError_not_supported_operation;
    }
#endif
    return UMSocketError_no_error;
}

- (UMSocketError) setSctpOptionReusePort
{
#ifdef SCTP_REUSE_PORT
    char on = 1;
    if(setsockopt(_sock, IPPROTO_SCTP, SCTP_REUSE_PORT, (char *)&on, sizeof(on)))
    {
        /* FIXME: use errno for proper return */
        return UMSocketError_not_supported_operation;
    }
#endif
    return UMSocketError_no_error;
}

- (UMSocketError)    bind;
{
    int usable_ips = -1;
    NSMutableArray *usable_addresses = [[NSMutableArray alloc]init];
    for(NSString *address in self.requestedLocalAddresses)
    {
        struct sockaddr_in        local_addr;
        memset(&local_addr,0x00,sizeof(local_addr));
        
        local_addr.sin_family = AF_INET;
    #ifdef __APPLE__
        local_addr.sin_len         = sizeof(struct sockaddr_in);
    #endif
        
        inet_aton(address.UTF8String, &local_addr.sin_addr);
        local_addr.sin_port = htons(self.requestedLocalPort);
        
        if(usable_ips == -1)
        {
            int err = bind(_sock, (struct sockaddr *)&local_addr,sizeof(local_addr));
            if(err == 0)
            {
                usable_ips = 1;
                [usable_addresses addObject:address];
            }
        }
        else
        {
            int err = sctp_bindx(_sock, (struct sockaddr *)&local_addr,1,SCTP_BINDX_ADD_ADDR);
            if(err==0)
            {
                usable_ips++;
                [usable_addresses addObject:address];
            }
        }
    }
    if(usable_ips <= 0)
    {
        return UMSocketError_address_not_available;
    }
    else
    {
        return UMSocketError_no_error;
    }
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
    event.sctp_send_failure_event        = 1;
    event.sctp_peer_error_event            = 1;
    event.sctp_shutdown_event            = 1;
    event.sctp_partial_delivery_event    = 1;
    event.sctp_adaptation_layer_event    = 1;
    event.sctp_authentication_event        = 1;
#ifndef LINUX
    event.sctp_stream_reset_events        = 1;
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
        NSString *address = [_requestedRemoteAddresses objectAtIndex:i];
        inet_aton(address.UTF8String, &remote_addresses[i].sin_addr);
        remote_addresses[i].sin_port = htons(requestedRemotePort);
    }
    int err =  sctp_connectx(_sock,(struct sockaddr *)&remote_addresses[0],remote_addresses_count,&assoc);
    free(remote_addresses);
    remote_addresses = NULL;
    if ((err < 0) && (err !=EINPROGRESS))
    {
        if(errno != EINPROGRESS)
        {
            return [UMSocket umerrFromErrno:(UMSocketError)errno];
        }
    }
    return UMSocketError_no_error;
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
            newcon.requestedLocalPort=requestedLocalPort;
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

#define SCTP_RXBUF 2048

- (UMSocketError)receiveSCTP /* returns number of packets processed and calls the notification and or data delegate */
{
    char                    buffer[SCTP_RXBUF+1];
    int                     flags;
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
    if(bytes_read == 0)
    {
        if(errno==ECONNRESET)
        {
            return UMSocketError_connection_reset;
        }
    }
    if(bytes_read <= 0)
    {
        /* we are having a non blocking read here */
        return [UMSocket umerrFromErrno:errno];
    }
    
    NSData *data = [NSData dataWithBytes:&buffer length:bytes_read];
    if(flags & _msg_notification_mask)
    {
        return [_notificationDelegate handleEvent:data
                                           sinfo:&sinfo];
    }
    else
    {
        uint16_t streamId = sinfo.sinfo_stream;
        uint32_t protocolId = ntohl(sinfo.sinfo_ppid);
        
        return [_dataDelegate sctpReceivedData:data
                                      streamId:streamId
                                    protocolId:protocolId];
    }
    return 1;
}
@end
