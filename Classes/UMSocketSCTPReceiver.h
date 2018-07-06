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

/*  UMSocketSCTPReceiver is a backgrounder tasks which listens to all
    sctp sockets (listeners and outgoing connections) and receives
    their packets and hands them over to the proper UMSocketSCTPListener
    or UMLayerSctp object */
@class UMSocketSCTPRegistry;

@interface UMSocketSCTPReceiver : UMBackgrounder
{
    NSMutableArray<UMLayerSctp *> *_outboundLayers;
    NSMutableArray<UMSocketSCTPListener *> *_listeners;
    //UMMutex *_lock;
    int _timeoutInMs;
    UMSocketSCTPRegistry *_registry;
}

- (UMSocketSCTPReceiver *)initWithRegistry:(UMSocketSCTPRegistry *)_registry;

@end
