//
//  UMSctpTask_Close.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright (c) 2016 Andreas Fink
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"
@class UMLayerSctp;

@interface UMSctpTask_Close : UMLayerTask

- (UMSctpTask_Close *)initWithReceiver:(UMLayerSctp *)rx sender:(id<UMLayerSctpUserProtocol>)tx;
- (void)main;
@end
