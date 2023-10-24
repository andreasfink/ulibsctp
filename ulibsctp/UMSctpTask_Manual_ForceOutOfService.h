//
//  UMSctpTask_Manual_ForceOutOfService.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import <ulibsctp/UMLayerSctp.h>
#import <ulibsctp/UMLayerSctpUserProtocol.h>

@interface UMSctpTask_Manual_ForceOutOfService : UMLayerTask
{
    
}

- (UMSctpTask_Manual_ForceOutOfService *)initWithReceiver:(UMLayerSctp *)rx sender:(id<UMLayerSctpUserProtocol>)tx;
- (void)main;

@end
