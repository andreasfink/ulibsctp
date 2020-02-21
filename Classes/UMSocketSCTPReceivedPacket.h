//
//  UMSocketSCTPReceivedPacket.h
//  ulibsctp
//
//  Created by Andreas Fink on 18.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>

@interface UMSocketSCTPReceivedPacket : UMObject
{
    UMSocketError _err;
    uint16_t    _streamId;
    uint32_t    _protocolId;
    uint32_t    _context;
    NSNumber    *_assocId;
    NSNumber    *_socket;
    NSData      *_data;
    NSString    *_remoteAddress;
    int         _remotePort;
    NSString    *_localAddress;
    int         _localPort;
    int         _flags;
    BOOL        _isNotification;

    UMMicroSec  _poll_time;
    UMMicroSec  _rx_time;
    UMMicroSec  _process_time;
}

@property(readwrite,atomic,assign)  UMSocketError err;
@property(readwrite,atomic,assign)  uint16_t streamId;
@property(readwrite,atomic,assign)  uint32_t protocolId;
@property(readwrite,atomic,assign)  uint32_t context;
@property(readwrite,atomic,strong)  NSNumber *socket;
@property(readwrite,atomic,strong)  NSNumber *assocId;
@property(readwrite,atomic,strong)  NSData *data;
@property(readwrite,atomic,strong)  NSString *remoteAddress;
@property(readwrite,atomic,assign)  int remotePort;
@property(readwrite,atomic,strong)  NSString *localAddress;
@property(readwrite,atomic,assign)  int localPort;
@property(readwrite,atomic,assign)  int flags;
@property(readwrite,atomic,assign)  BOOL isNotification;
@property(readwrite,atomic,assign)  UMMicroSec  poll_time;
@property(readwrite,atomic,assign)  UMMicroSec  rx_time;
@property(readwrite,atomic,assign)  UMMicroSec  process_time;

@end
