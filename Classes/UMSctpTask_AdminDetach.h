//
//  UMSctpTask_AdminDetach.h
//  ulibsctp
//
//  Created by Andreas Fink on 02.12.14.
//  Copyright (c) 2016 Andreas Fink
//

#import <ulib/ulib.h>
@class UMLayerSctp;
#import "UMLayerSctpUserProtocol.h"

@interface UMSctpTask_AdminDetach : UMLayerTask
{
    id       userId;
}

@property(readwrite,strong) id userId;

- (UMSctpTask_AdminDetach *)initWithReceiver:(UMLayerSctp *)rx
                                      sender:(id<UMLayerSctpUserProtocol>)tx
                                      userId:(id)uid;
- (void)main;

@end
