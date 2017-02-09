//
//  UMSctpTask_Manual_InService.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>

#import "UMLayerSctp.h"
#import "UMLayerSctpUserProtocol.h"

@interface UMSctpTask_Manual_InService : UMLayerTask
{
}

- (UMSctpTask_Manual_InService *)initWithReceiver:(UMLayerSctp *)rx sender:(id<UMLayerSctpUserProtocol>)tx;
- (void)main;

@end
