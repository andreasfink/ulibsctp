//
//  UMLayerSctpUser.h
//  ulibsctp
//
//  Created by Andreas Fink on 02.12.14.
//  Copyright (c) 2016 Andreas Fink
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"

@class UMLayerSctpUserProfile;

@interface UMLayerSctpUser : UMObject
{
    id<UMLayerSctpUserProtocol> __weak  user;
    UMLayerSctpUserProfile              *profile;
    id                                  userId;
}

@property(readwrite,weak)   id<UMLayerSctpUserProtocol> user;
@property(readwrite,strong) UMLayerSctpUserProfile     *profile;
@property(readwrite,strong) id                          userId;

@end
