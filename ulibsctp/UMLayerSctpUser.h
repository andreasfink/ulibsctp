//
//  UMLayerSctpUser.h
//  ulibsctp
//
//  Created by Andreas Fink on 02.12.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMLayerSctpUserProtocol.h"

@class UMLayerSctpUserProfile;

@interface UMLayerSctpUser : UMObject
{
    id<UMLayerSctpUserProtocol>         user;
    UMLayerSctpUserProfile              *profile;
    id                                  userId;
}

@property(readwrite,strong)   id<UMLayerSctpUserProtocol> user;
@property(readwrite,strong) UMLayerSctpUserProfile     *profile;
@property(readwrite,strong) id                          userId;

@end
