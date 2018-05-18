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
    NSData      *_data;
    NSString    *_remoteAddress;
    int         _flags;
    BOOL        _isNotification;
}

@property(readwrite,atomic,assign)  UMSocketError err;
@property(readwrite,atomic,assign)  uint16_t streamId;
@property(readwrite,atomic,assign)  uint32_t protocolId;
@property(readwrite,atomic,assign)  uint32_t context;
@property(readwrite,atomic,strong)  NSNumber *assocId;
@property(readwrite,atomic,strong)  NSData *data;
@property(readwrite,atomic,strong)  NSString *remoteAddress;
@property(readwrite,atomic,assign)  int flags;
@property(readwrite,atomic,assign) BOOL isNotification;

@end
