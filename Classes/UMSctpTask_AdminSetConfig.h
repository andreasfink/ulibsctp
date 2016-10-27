//
//  UMSctpTask_AdminSetConfig.h
//  ulibsctp
//
//  Created by Andreas Fink on 01.12.14.
//  Copyright (c) 2016 Andreas Fink
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"

@class UMLayerSctp;

@interface UMSctpTask_AdminSetConfig : UMLayerTask
{
    NSDictionary *config;
}
@property(readwrite,strong)     NSDictionary *config;

- (UMSctpTask_AdminSetConfig *)initWithReceiver:(UMLayerSctp *)receiver config:(NSDictionary *)cfg;
- (void)main;

@end
