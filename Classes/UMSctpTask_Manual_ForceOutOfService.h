//
//  UMSctpTask_Manual_ForceOutOfService.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright (c) 2016 Andreas Fink
//

#import <ulib/ulib.h>
#import "UMLayerSctp.h"
#import "UMLayerSctpUserProtocol.h"

@interface UMSctpTask_Manual_ForceOutOfService : UMLayerTask
{
    
}

- (UMSctpTask_Manual_ForceOutOfService *)initWithReceiver:(UMLayerSctp *)rx sender:(id<UMLayerSctpUserProtocol>)tx;
- (void)main;

@end
