//
//  UMSctpOverTcp.h
//  ulibsctp
//
//  Created by Andreas Fink on 11.12.20.
//  Copyright © 2020 Andreas Fink (andreas@fink.org). All rights reserved.
//


typedef struct sctp_over_tcp_header
{
    /* on the wire, all in network byte order */
    uint32_t    header_length;
    uint32_t    payload_length;
    uint32_t    protocolId;
    uint16_t    streamId;
    uint16_t    flags;
} sctp_over_tcp_header;
