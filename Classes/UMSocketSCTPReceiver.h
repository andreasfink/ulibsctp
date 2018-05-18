//
//  UMSocketSCTPReceiver.h
//  ulibsctp
//
//  Created by Andreas Fink on 18.05.18.
//  Copyright © 2018 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
@class UMLayerSctp;
@class UMSocketSCTPListener;
@interface UMSocketSCTPReceiver : UMBackgrounder
{
    NSMutableArray<UMLayerSctp *> *_outboundLayers;
    NSMutableArray<UMSocketSCTPListener *> *_listeners;
    UMMutex *_lock;
    int _timeoutInMs;
}
@end
