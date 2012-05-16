// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "MenuEntry.h"
#import "GetUniqueID.h"

#include <sys/types.h>  /* for type definitions */
#include <sys/socket.h> /* for socket API calls */
#include <netinet/in.h> /* for address structs */
#include <arpa/inet.h>  /* for sockaddr_in */
#include <sys/types.h>
#include <sys/time.h>

@implementation MenuEntry
@synthesize ns;
@synthesize menuItem;

- (NSString *) name {
	return [ns name];
}
- (id)initWithNS:(NSNetService *)nse andMenuItem:(NSMenuItem *)item {
    self = [super init];
    if (self) {
		ns = nse;
		menuItem = item;
		[menuItem retain];
		sessID = nil;
    }
    
    return self;
}

- (void)updateNS: nse {
	NSDictionary *myKeys = [NSNetService dictionaryFromTXTRecordData:[nse TXTRecordData]];
	NSData *data = [myKeys objectForKey:@"name"];
	NSString *fullName = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
	[menuItem setTitle:fullName];
    [fullName release];
    
	[ns stop];
	ns = nse;
}

- (void)removeEntry:(NSMenu *)menu {
	[ns stop];
	if (sessID != nil)
		[sessID release];
	[menu removeItem:menuItem];
	[menuItem release];
}

- (IBAction)projectAction:(id)sender {
#pragma unused(sender)
	
	int remoteSocket = socket(AF_INET, SOCK_STREAM, 0);
	boolean_t connected = false;
    NSArray *addresses = [ns addresses];
    NSUInteger arrayCount = [addresses count];
    for (unsigned long i = 0; i < arrayCount; i++) {
        NSData *address = [addresses objectAtIndex:i];
        struct sockaddr_in *address_sin = (struct sockaddr_in *)[address bytes];
        
        char buffer[1024];
        NSLog(@"DEBUG: Trying... %s:%d", inet_ntop(AF_INET, &(address_sin->sin_addr), buffer, sizeof(buffer)), ntohs(address_sin->sin_port));
        
        if (address_sin->sin_family == AF_INET) {
            if (connect(remoteSocket, (struct sockaddr *)address_sin, (socklen_t)sizeof(struct sockaddr_in)) == 0) {
                connected = true;
                
                break;
            }
        }
    }
    
	if (connected) {
		int set = 1;
		setsockopt(remoteSocket, SOL_SOCKET, SO_NOSIGPIPE, (void *)&set, sizeof(int));
			
		if (sessID == nil) {
			GetUniqueID *uniqid = [[GetUniqueID alloc] init];
			NSString *myUniqueID = [NSString stringWithFormat:@"streamer-%@", [uniqid GetHWAddress]];
			NSString *streamerID = [[NSUserDefaults standardUserDefaults] stringForKey:myUniqueID];
			NSString *cmd = [[NSString alloc] initWithFormat:@"SHOW %@ FULLSCREEN\n", streamerID];
			NSLog(@"CMD: %@", cmd);
			NSData *data = [cmd dataUsingEncoding:NSUTF8StringEncoding];
			
			send(remoteSocket, [data bytes], [data length], 0);
           [uniqid release];
			[cmd release];
				// [data release];
			
			fd_set readfds;
			struct timeval timeout;
			
			FD_ZERO(&readfds);
			FD_SET(remoteSocket, &readfds);
			timeout.tv_sec = 5;
			timeout.tv_usec = 0;
			
			if (select(remoteSocket + 1, &readfds, NULL, NULL, &timeout) > 0) {
				if (FD_ISSET(remoteSocket, &readfds)) {
					char buf[1024];
					NSUInteger recvLength = recv(remoteSocket, buf, 1024, 0);
					data = [NSData dataWithBytes: buf length:recvLength];
					sessID = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] retain];
					NSLog(@"SessionID: %@", sessID);

					[menuItem setState:NSOnState];
				}
			} else {
				NSLog(@"Timeout waiting for remote session creation");
				
				[menuItem setState:NSOffState];
				[sessID release];
				sessID = nil;
			}
		} else {
			NSString *cmd = [[NSString alloc] initWithFormat:@"CLOSE %@\n", sessID];
			NSData *data = [cmd dataUsingEncoding:NSUTF8StringEncoding];
			
			NSLog(@"Command: %@", cmd);
			
			send(remoteSocket, [data bytes], [data length], 0);
			[cmd release];
				// [data release];
			
				// No need to wait for results that we dont really care for 
				// char buf[1024];
				// NSUInteger recvLength = recv(remoteSocket, buf, 1024, 0);
				// data = [NSData dataWithBytes: buf length:recvLength];
				// NSLog(@"Session closed with message: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
			
			close(remoteSocket);
			[sessID release];
			sessID = nil;
			[menuItem setState:NSOffState];
		}
		
		close(remoteSocket);
	}
}
@end
