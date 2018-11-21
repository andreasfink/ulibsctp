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
#include <netinet/sctp.h>
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
    double          _heartbeatSeconds;
    NSTimeInterval  _connectionRepeatTimer;

    UMSocketSCTPListener *_listener;
    BOOL            _continuousConnectionAttempts;

    NSData              *_localAddressesSockaddr;
    int                 _localAddressesSockaddrCount;
//    struct sockaddr     *_local_addresses;
//    int                 _local_addresses_count;
//    BOOL                _local_addresses_prepared;
  //  sctp_assoc_t        assoc;
    int         _mtu;
}

@property(readwrite,strong) NSArray        *requestedLocalAddresses;
@property(readwrite,strong) NSArray        *connectedLocalAddresses;
@property(readwrite,strong) NSArray        *requestedRemoteAddresses;
@property(readwrite,strong) NSArray        *connectedRemoteAddresses;
@property(readwrite,assign) int            msg_notification_mask;
@property(readwrite,assign) double            heartbeatSeconds;
@property(readwrite,strong) id<UMSocketSCTP_notificationDelegate>   notificationDelegate;
@property(readwrite,strong) id<UMSocketSCTP_dataDelegate>           dataDelegate;
@property(readwrite,assign) BOOL            continuousConnectionAttempts;
@property(readwrite,assign) NSTimeInterval  connectionRepeatTimer;
@property(readwrite,assign) int mtu;

- (UMSocketError) bind;
- (UMSocketError) enableEvents;
- (UMSocketError) enableFutureAssoc;

- (UMSocketSCTP *) acceptSCTP:(UMSocketError *)ret;
//- (UMSocketError) connectSCTP;


+ (NSData *)sockaddrFromAddresses:(NSArray *)theAddrs
                             port:(int)thePort
                            count:(int *)count_out /* returns struct sockaddr data in NSData */
                     socketFamily:(int)socketFamily;

- (UMSocketError) connectToAddresses:(NSArray *)addrs
                                port:(int)remotePort
                               assoc:(sctp_assoc_t *)assoc;

- (ssize_t) sendToAddresses:(NSArray *)addrs
                       port:(int)port
                      assoc:(sctp_assoc_t *)assoc
                       data:(NSData *)data
                     stream:(uint16_t)streamId
                   protocol:(u_int32_t)protocolId
                      error:(UMSocketError *)err2;
/*
- (ssize_t)sendSCTP:(NSData *)data
             stream:(uint16_t)streamId
           protocol:(u_int32_t)protocolId
              error:(UMSocketError *)err;
 */
- (UMSocketSCTPReceivedPacket *)receiveSCTP;

- (UMSocketError) dataIsAvailableSCTP:(int)timeoutInMs
                            dataAvail:(int *)hasData
                               hangup:(int *)hasHup;
- (UMSocketError) getSocketError;
- (UMSocketError) setReusePort;
- (UMSocketError) setNoDelay;
- (void)updateMtu:(int)newMtu;

@end
