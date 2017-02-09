//
//  UMSctpTask_AdminAttach.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSctpTask_AdminAttach.h"
#import "UMLayerSctp.h"
#import "UMLayerSctpUserProtocol.h"
#import "UMLayerSctpUserProfile.h"

@implementation UMSctpTask_AdminAttach
@synthesize profile;
@synthesize userId;

- (UMSctpTask_AdminAttach *)initWithReceiver:(UMLayerSctp *)rx
                                      sender:(id<UMLayerSctpUserProtocol>)tx
                                     profile:(UMLayerSctpUserProfile *)p
                                      userId:(id)uid;
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:tx
       requiresSynchronisation:NO];
    if(self)
    {
        self.name = @"UMSctpTask_AdminAttach";
        self.profile = p;
    }
    return self;
}

- (void)main
{
    UMLayerSctp *link = (UMLayerSctp *)self.receiver;
    [link _adminAttachTask:self];
}

@end
