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
#import "UMSocketSCTPReceivedPacket.h"
#ifdef __APPLE__
#import <sctp/sctp.h>
#else
#include "/usr/local/include/netinet/sctp.h"
#endif

@class UMSocketSCTPListener;

@protocol UMSocketSCTP_notificationDelegate
- (UMSocketError) handleEvent:(NSData *)data
                        sinfo:(struct sctp_sndrcvinfo *)sinfo;
@end

@protocol UMSocketSCTP_dataDelegate
- (UMSocketError) sctpReceivedData:(NSData *)data
                          streamId:(uint32_t)streamId
                        protocolId:(uint16_t)protocolId;
@end


    
@interface UMSocketSCTP : UMSocket
{
    NSArray         *_requestedLocalAddresses;
    NSArray         *_useableLocalAddresses;
    NSArray         *_connectedLocalAddresses;
    NSArray         *_requestedRemoteAddresses;
    NSArray         *_connectedRemoteAddresses;
    int             _msg_notification_mask;
    int             _heartbeatMs;
    NSTimeInterval  _connectionRepeatTimer;

    UMSocketSCTPListener *_listener;
    BOOL            _continuousConnectionAttempts;
    
    struct sockaddr     *_remote_addresses;
    int                 _remote_addresses_count;
    BOOL                _remote_addresses_prepared;
    struct sockaddr     *_local_addresses;
    int                 _local_addresses_count;
    BOOL                _local_addresses_prepared;
    sctp_assoc_t        assoc;
}

@property(readwrite,strong) NSArray        *requestedLocalAddresses;
@property(readwrite,strong) NSArray        *connectedLocalAddresses;
@property(readwrite,strong) NSArray        *requestedRemoteAddresses;
@property(readwrite,strong) NSArray        *connectedRemoteAddresses;
@property(readwrite,assign) int            msg_notification_mask;
@property(readwrite,assign) int            heartbeatMs;
@property(readwrite,strong) id<UMSocketSCTP_notificationDelegate>   notificationDelegate;
@property(readwrite,strong) id<UMSocketSCTP_dataDelegate>           dataDelegate;
@property(readwrite,assign) BOOL            continuousConnectionAttempts;
@property(readwrite,assign) NSTimeInterval  connectionRepeatTimer;


- (NSNumber *)assocId;
- (UMSocketError) bind;
- (UMSocketError) enableEvents;
- (UMSocketSCTP *) acceptSCTP:(UMSocketError *)ret;
- (UMSocketError) connectSCTP;
- (ssize_t)sendSCTP:(NSData *)data
             stream:(uint16_t)streamId
           protocol:(u_int32_t)protocolId
              error:(UMSocketError *)err;
- (UMSocketSCTPReceivedPacket *)receiveSCTP;

- (UMSocketError) dataIsAvailableSCTP:(int)timeoutInMs
                            dataAvail:(int *)hasData
                               hangup:(int *)hasHup;
- (UMSocketError) getSocketError;
- (UMSocketError) setReusePort;
- (UMSocketError) setNoDelay;

@end
