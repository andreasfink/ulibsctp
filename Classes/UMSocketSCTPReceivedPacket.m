//
//  UMSocketSCTPReceivedPacket.m
//  ulibsctp
//
//  Created by Andreas Fink on 18.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPReceivedPacket.h"

@implementation UMSocketSCTPReceivedPacket

- (NSString *)description
{
    NSMutableString *s = [[NSMutableString alloc]init];
    [s appendFormat:@"-----------------------------------------------------------\n"];
    [s appendFormat:@"UMSocketSCTPReceivedPacket %p\n",self];
    [s appendFormat:@".err =  %d %@\n",_err,[UMSocket getSocketErrorString:_err]];
    [s appendFormat:@".streamId =  %lu\n",(unsigned long)_streamId];
    [s appendFormat:@".protocolId =  %lu\n",(unsigned long)_protocolId];
    [s appendFormat:@".context =  %lu\n",(unsigned long)_context];
    [s appendFormat:@".assocId =  %lu\n",(unsigned long)_assocId];
    [s appendFormat:@".remoteAddress = %@\n",_remoteAddress];
    [s appendFormat:@".rempotePort =  %d\n",_remotePort];
    [s appendFormat:@".isNotification =  %@\n",_isNotification ? @"YES" : @"NO"];
    [s appendFormat:@".flags =  %d\n",_flags];
    [s appendFormat:@".data =  %@\n",[_data hexString]];
    [s appendFormat:@"-----------------------------------------------------------\n"];
    return s;
}
@end
