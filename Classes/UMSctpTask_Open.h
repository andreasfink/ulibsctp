//
//  UMSctpTask_Open.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"

@class UMLayerSctp;

@interface UMSctpTask_Open : UMLayerTask
{
    BOOL _sendAbortFirst;
}
@property(readwrite,assign) BOOL sendAbortFirst;

- (UMSctpTask_Open *)initWithReceiver:(UMLayerSctp *)rx sender:(id<UMLayerSctpUserProtocol>)tx;
- (void)main;
@end
