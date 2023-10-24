//
//  UMSctpTask_AdminAttach.h
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
@class UMLayerSctp;
@class UMLayerSctpUserProfile;

#import <ulibsctp/UMLayerSctpUserProtocol.h>


@interface UMSctpTask_AdminAttach : UMLayerTask
{
    UMLayerSctpUserProfile *profile;
    id       userId;
}
@property(readwrite,strong) UMLayerSctpUserProfile *profile;
@property(readwrite,strong) id userId;

- (UMSctpTask_AdminAttach *)initWithReceiver:(UMLayerSctp *)rx
                                      sender:(id<UMLayerSctpUserProtocol>)tx
                                     profile:(UMLayerSctpUserProfile *)p
                                      userId:(id)uid;
- (void)main;

@end
