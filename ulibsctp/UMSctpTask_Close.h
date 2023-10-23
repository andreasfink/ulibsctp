//
//  UMSctpTask_Close.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"
@class UMLayerSctp;

@interface UMSctpTask_Close : UMLayerTask
{
    NSString *_reason;
}
@property(readwrite,strong,atomic) NSString *reason;

- (UMSctpTask_Close *)initWithReceiver:(UMLayerSctp *)rx sender:(id<UMLayerSctpUserProtocol>)tx;
- (void)main;
@end
