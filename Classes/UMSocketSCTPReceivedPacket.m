//
//  UMSocketSCTPReceivedPacket.m
//  ulibsctp
//
//  Created by Andreas Fink on 18.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPReceivedPacket.h"
#import "UMSctpOverTcp.h"

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
@implementation UMSocketSCTPReceivedPacket

- (NSString *)description
{
    NSMutableString *s = [[NSMutableString alloc]init];
    [s appendFormat:@"-----------------------------------------------------------\n"];
    [s appendFormat:@"UMSocketSCTPReceivedPacket %p\n",self];
    [s appendFormat:@".err =  %d %@\n",_err,[UMSocket getSocketErrorString:_err]];
    [s appendFormat:@".socket =  %@\n",_socket];
    [s appendFormat:@".streamId =  %lu\n",(unsigned long)_streamId];
    [s appendFormat:@".protocolId =  %lu\n",(unsigned long)_protocolId];
    [s appendFormat:@".context =  %lu\n",(unsigned long)_context];
    [s appendFormat:@".assocId =  %@\n",_assocId];
    [s appendFormat:@".remoteAddress = %@\n",_remoteAddress];
    [s appendFormat:@".rempotePort =  %d\n",_remotePort];
    [s appendFormat:@".localAddress = %@\n",_localAddress];
    [s appendFormat:@".localPort =  %d\n",_localPort];
    [s appendFormat:@".isNotification =  %@\n",_isNotification ? @"YES" : @"NO"];
    
    NSMutableArray *a = [[NSMutableArray alloc]init];
    if(_flags & MSG_NOTIFICATION)
    {
        [a addObject:@"MSG_NOTIFICATION"];
    }
    [s appendFormat:@".flags =  %d %@\n",_flags, [a componentsJoinedByString:@" | "]];
    
    a = [[NSMutableArray alloc]init];
    
    if(_tcp_flags & SCTP_OVER_TCP_NOTIFICATION)
    {
        [a addObject:@"SCTP_OVER_TCP_NOTIFICATION"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_COMPLETE)
    {
        [a addObject:@"SCTP_OVER_TCP_COMPLETE"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_EOF)
    {
        [a addObject:@"SCTP_OVER_TCP_EOF"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_ABORT)
    {
        [a addObject:@"SCTP_OVER_TCP_ABORT"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_UNORDERED)
    {
        [a addObject:@"SCTP_OVER_TCP_UNORDERED"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_ADDR_OVER)
    {
        [a addObject:@"SCTP_OVER_TCP_ADDR_OVER"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_SENDALL)
    {
        [a addObject:@"SCTP_OVER_TCP_SENDALL"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_EOR)
    {
        [a addObject:@"SCTP_OVER_TCP_EOR"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_SACK_IMMEDIATELY)
    {
        [a addObject:@"SCTP_OVER_TCP_SACK_IMMEDIATELY"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_SETUP)
    {
        [a addObject:@"SCTP_OVER_TCP_SETUP"];
    }
    if(_tcp_flags & SCTP_OVER_TCP_SETUP_CONFIRM)
    {
        [a addObject:@"SCTP_OVER_TCP_SETUP_CONFIRM"];
    }

    [s appendFormat:@".tcp_flags =  %d %@\n",_tcp_flags, [a componentsJoinedByString:@" | "]];
    [s appendFormat:@".data =  %@\n",[_data hexString]];
    [s appendFormat:@"-----------------------------------------------------------\n"];
    return s;
}

@end
