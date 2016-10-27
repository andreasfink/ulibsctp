//
//  UMLayerSctpStatus.h
//  ulibsctp
//
//  Created by Andreas Fink on 01/12/14.
//  Copyright (c) 2016 Andreas Fink
//

typedef	enum	SCTP_Status
{
    SCTP_STATUS_M_FOOS	= -11,	/* forced out of service manually */
    SCTP_STATUS_OFF		= 10,	/* currently no SCTP association or connection */
    SCTP_STATUS_OOS		= 11,	/* SCTP connection configured/requested but not established yet*/
    SCTP_STATUS_IS		= 12,	/* SCTP association/connection established */
} SCTP_Status;

