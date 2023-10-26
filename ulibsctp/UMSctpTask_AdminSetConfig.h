//
//  UMSctpTask_AdminSetConfig.h
//  ulibsctp
//
//  Created by Andreas Fink on 01.12.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import <ulibsctp/UMLayerSctpUserProtocol.h>

@class UMLayerSctp;

@interface UMSctpTask_AdminSetConfig : UMLayerTask
{
    NSDictionary *config;
    id          appContext;
}
@property(readwrite,strong)     NSDictionary *config;

- (UMSctpTask_AdminSetConfig *)initWithReceiver:(UMLayerSctp *)receiver
                                         config:(NSDictionary *)cfg
                             applicationContext:(id)appContext;
- (void)main;
- (id)appContext;
@end
