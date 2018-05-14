//
//  UMSocketSCTP.h
//  ulibsctp
//
//  Created by Andreas Fink on 14.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMLayerSctpStatus.h"
#import "UMLayerSctpUserProtocol.h"
#import "UMLayerSctpApplicationContextProtocol.h"
struct sctp_sndrcvinfo;

@protocol UMSocketSCTP_notificationDelegate
- (void) handleEvent:(NSString *)data sinfo:(struct sctp_sndrcvinfo *)sinfo;
@end

@protocol UMSocketSCTP_dataDelegate
- (void) sctpReceivedData:(NSData *)data
                 streamId:(uint32_t)streamId
               protocolId:(uint16_t)protocolId;
@end


    
@interface UMSocketSCTP : UMSocket
{
    NSArray         *_requestedLocalAddresses;
    NSArray         *_connectedLocalAddresses;
    NSArray         *_requestedRemoteAddresses;
    NSArray         *_connectedRemoteAddresses;
    int             _msg_notification_mask;
    int             _heartbeatMs;
    id<UMSocketSCTP_notificationDelegate> __weak _notificationDelegate;
    id<UMSocketSCTP_dataDelegate>         __weak _dataDelegate;
}

@property(readwrite,strong) NSArray        *requestedLocalAddresses;
@property(readwrite,strong) NSArray        *connectedLocalAddresses;
@property(readwrite,strong) NSArray        *requestedRemoteAddresses;
@property(readwrite,strong) NSArray        *connectedRemoteAddresses;
@property(readwrite,assign) int            msg_notification_mask;
@property(readwrite,assign) int            heartbeatMs;
@property(readwrite,weak) id<UMSocketSCTP_notificationDelegate>   notificationDelegate;
@property(readwrite,weak) id<UMSocketSCTP_dataDelegate>           dataDelegate;

- (UMSocketError) setSctpOptionNoDelay;
- (UMSocketError) setSctpOptionReusePort;
- (UMSocketError) enableEvents;
- (UMSocketSCTP *) acceptSCTP:(UMSocketError *)ret;
- (UMSocketError) connectSCTP;
- (ssize_t)sendSCTP:(NSData *)data
             stream:(uint16_t)streamId
           protocol:(u_int32_t)protocolId
              error:(UMSocketError *)err;
- (UMSocketError)receiveSCTP; /* returns number of packets processed */

@end
