//
//  UMSocketSCTP.h
//  ulibsctp
//
//  Created by Andreas Fink on 14.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"
#import "UMLayerSctpApplicationContextProtocol.h"
#import "UMSocketSCTPReceivedPacket.h"

struct sctp_sndrcvinfo;


typedef enum SCTP_SocketType_enum
{
    SCTP_SOCKET_TYPE_LISTENER_SCTP  = 0,
    SCTP_SOCKET_TYPE_LISTENER_TCP   = 1,
    SCTP_SOCKET_TYPE_OUTBOUND       = 2,
    SCTP_SOCKET_TYPE_INBOUND        = 3,
    SCTP_SOCKET_TYPE_OUTBOUND_TCP   = 4,
    SCTP_SOCKET_TYPE_INBOUND_TCP    = 5,
} SCTP_SocketType_enum;

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
    BOOL            _connectx_pending;
    NSData          *_localAddressesSockaddr;
    int             _localAddressesSockaddrCount;
    int             _mtu;
    int             _maxSeg;
    int             _maxInStreams;
    int             _numOStreams;
    int             _maxInitAttempts;
    int             _initTimeout;
	NSNumber		*_xassoc;
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
@property(readwrite,assign) int maxInStreams;
@property(readwrite,assign) int numOStreams;
@property(readwrite,assign) int maxInitAttempts;
@property(readwrite,assign) int initTimeout;

@property(readwrite,strong)	NSNumber		*xassoc;


- (int)maxSegment;
- (void)setMaxSegment:(int)newMaxSeg;

- (UMSocketError) bind;
- (UMSocketError) enableEvents;
- (UMSocketError) enableFutureAssoc;

- (UMSocketSCTP *) acceptSCTP:(UMSocketError *)ret;
- (UMSocketSCTP *) peelOffAssoc:(uint32_t)assoc
						  error:(UMSocketError *)errptr;

- (UMSocketError) connect;
- (UMSocketError) connectAssoc:(uint32_t *)assoc;
- (UMSocketError) connectToAddresses:(NSArray *)addrs
                                port:(int)remotePort
                               assoc:(uint32_t *)assoc;


+ (NSData *)sockaddrFromAddresses:(NSArray *)theAddrs
                             port:(int)thePort
                            count:(int *)count_out /* returns struct sockaddr data in NSData */
                     socketFamily:(int)socketFamily;

- (ssize_t) sendToAddresses:(NSArray *)addrs
                       port:(int)port
                      assoc:(uint32_t *)assoc
                       data:(NSData *)data
                     stream:(uint16_t)streamId
                   protocol:(u_int32_t)protocolId
                      error:(UMSocketError *)err2;



- (UMSocketError) abortToAddress:(NSString *)addr
                            port:(int)remotePort
                           assoc:(uint32_t)assoc
                          stream:(uint16_t)streamId
                        protocol:(u_int32_t)protocolId;

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
- (UMSocketError) setInitParams;

- (void)updateMtu:(int)newMtu;
- (UMSocketError)setHeartbeat:(BOOL)enable;
- (NSArray *)getRemoteIpAddressesForAssoc:(uint32_t)assoc;
- (int)bindx:(struct sockaddr *)localAddress;
@end
