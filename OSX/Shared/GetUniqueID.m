// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "GetUniqueID.h"

#include <sys/ioctl.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <sys/sockio.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/ethernet.h>
#include <net/if_types.h>

@implementation GetUniqueID

#define BUFFERSIZE	4096
#define MAXADDRS	32
#define	max(a,b)	((a) > (b) ? (a) : (b))

- (NSString *)GetHWAddress {
	struct ifconf ifc;
	struct ifreq *ifr;
	int i, sockfd;
	char buffer[BUFFERSIZE], *cp, *cplim;
	char *hw_addrs[MAXADDRS];
	
	for (i=0; i<MAXADDRS; ++i)
		hw_addrs[i] = NULL;
	
	sockfd = socket(AF_INET, SOCK_DGRAM, 0);
	if (sockfd < 0) 
		return nil;
	
	ifc.ifc_len = BUFFERSIZE;
	ifc.ifc_buf = buffer;
	if (ioctl(sockfd, SIOCGIFCONF, (char *)&ifc) < 0) 
		return nil;
	close(sockfd);
	
		// ifr = ifc.ifc_req;
	cplim = buffer + ifc.ifc_len;
	for (cp=buffer; cp < cplim; ) {
		ifr = (struct ifreq *)cp;
		
		if (ifr->ifr_addr.sa_family == AF_LINK) {
			struct sockaddr_dl *sdl = (struct sockaddr_dl *)&ifr->ifr_addr;
			
			if (sdl->sdl_type == IFT_ETHER)
				return [[NSString alloc] initWithCString:(char *)ether_ntoa((struct ether_addr *)LLADDR(sdl)) encoding:NSUTF8StringEncoding];
		}
		cp += sizeof(ifr->ifr_name) + max(sizeof(ifr->ifr_addr), ifr->ifr_addr.sa_len);
	}
	return nil;
}

@end
