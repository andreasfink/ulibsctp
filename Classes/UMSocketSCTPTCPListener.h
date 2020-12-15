//
//  UMSocketSCTPTCPListener.h
//  ulibsctp
//
//  Created by Andreas Fink on 14.12.20.
//  Copyright © 2020 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import "UMSocketSCTPListener.h"

@interface UMSocketSCTPTCPListener : UMSocketSCTPListener
{
    UMSocket                    *_umsocketTcp;
}

- (UMSocketSCTPTCPListener *)initWithPort:(int)localPort;

@property(readwrite,strong) UMSocket *umsocketTcp;

@end
