//
//  UMSctpTask_Manual_InService.m
//  ulibsctp
//
//  Created by Andreas Fink on 29.11.14.
//  Copyright (c) 2016 Andreas Fink
//

#import "UMSctpTask_Manual_InService.h"
#import "UMLayerSctp.h"
#import "UMLayerSctpUserProtocol.h"

@implementation UMSctpTask_Manual_InService

- (UMSctpTask_Manual_InService *)initWithReceiver:(UMLayerSctp *)rx
                                           sender:(id<UMLayerSctpUserProtocol>)tx
{
    self = [super initWithName:[[self class]description]
                      receiver:rx
                        sender:tx
       requiresSynchronisation:YES];
    if(self)
    {
        self.name = @"UMSctpTask_Manual_InService";
    }
    return self;
}

-(void)main
{
    UMLayerSctp *link = (UMLayerSctp *)self.receiver;
    [link _isTask:self];
}



@end
