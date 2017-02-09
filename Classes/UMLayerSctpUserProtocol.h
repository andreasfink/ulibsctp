//
//  UMLayerSctpUserProtocol.h
//  ulibsctp
//
//  Created by Andreas Fink on 01/12/14.
//  Copyright © 2017 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <ulib/ulib.h>
#import "UMLayerSctpStatus.h"

/* these are the methods a user of the SctpLayer has to implement */
/* usually its a UMLayerObject where those methods simply queue an 
  operation on to the scheduling queue */

@protocol UMLayerSctpUserProtocol<UMLayerUserProtocol>

- (NSString *)layerName;

- (void) sctpStatusIndication:(UMLayer *)caller
                       userId:(id)uid
                       status:(SCTP_Status)s;

- (void) sctpDataIndication:(UMLayer *)caller
                     userId:(id)uid
                   streamId:(uint16_t)sid
                 protocolId:(uint32_t)pid
                       data:(NSData *)d;

- (void) sctpMonitorIndication:(UMLayer *)caller
                        userId:(id)uid
                      streamId:(uint16_t)sid
                    protocolId:(uint32_t)pid
                          data:(NSData *)d
                      incoming:(BOOL)in;

- (void) adminAttachConfirm:(UMLayer *)attachedLayer
                     userId:(id)uid;

- (void) adminAttachFail:(UMLayer *)attachedLayer
                  userId:(id)uid
                  reason:(NSString *)reason;

- (void) adminDetachConfirm:(UMLayer *)attachedLayer
                     userId:(id)uid;

- (void) adminDetachFail:(UMLayer *)attachedLayer
                  userId:(id)uid
                  reason:(NSString *)reason;

- (void)sentAckConfirmFrom:(UMLayer *)sender
                  userInfo:(NSDictionary *)userInfo;

- (void)sentAckFailureFrom:(UMLayer *)sender
                  userInfo:(NSDictionary *)userInfo
                     error:(NSString *)err
                    reason:(NSString *)reason
                 errorInfo:(NSDictionary *)ei;


@end
