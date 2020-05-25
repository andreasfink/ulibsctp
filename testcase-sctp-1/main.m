//
//  main.m
//  testcase-sctp-1
//
//  Created by Andreas Fink on 25.05.20.
//  Copyright © 2020 Andreas Fink (andreas@fink.org). All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ulibsctp/ulibsctp.h>

void testcase(NSString *s);

int main(int argc, const char * argv[])
{
    fprintf(stderr,"Start\n");
    sleep(120);
    for(int i=0;i<10000000;i++)
    {
        testcase(@"1.1.1.1");
        if((i % 100000)==0)
        {
            fprintf(stderr,"%d\n",i);
        }
    }
    fprintf(stderr,"Done\n");
    sleep(120);
    return 0;
}


void testcase(NSString *s)
{
    @autoreleasepool
    {
        int count_out;
        NSArray *theAddrs = @[s];
        NSData *d = [UMSocketSCTP sockaddrFromAddresses:theAddrs
                                                   port:123
                                                  count:&count_out /* returns struct sockaddr data in NSData */
                                           socketFamily:AF_INET];
    }
}
