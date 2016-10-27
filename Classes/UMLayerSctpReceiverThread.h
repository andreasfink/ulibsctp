//
//  UMLayerSctpReceiverThread.h
//  ulibsctp
//
//  Created by Andreas Fink on 01/12/14.
//  Copyright (c) 2016 Andreas Fink
//

#import <ulib/ulib.h>
@class UMLayerSctp;

@interface UMLayerSctpReceiverThread : UMBackgrounder
{
    UMLayerSctp *link;
}

-(UMLayerSctpReceiverThread *)initWithSctpLink:(UMLayerSctp *)lnk;

@end
