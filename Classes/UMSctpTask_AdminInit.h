//
//  UMSctpTask_AdminInit.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright (c) 2016 Andreas Fink
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"

@class UMLayerSctp;
@interface UMSctpTask_AdminInit : UMLayerTask

- (UMSctpTask_AdminInit *)initWithReceiver:(UMLayerSctp *)receiver sender:(id<UMLayerSctpUserProtocol>)sender;

@end

