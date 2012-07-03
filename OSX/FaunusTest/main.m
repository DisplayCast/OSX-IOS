//
//  main.m
//  FaunusTest
//
//  Created by Surendar Chandra on 6/27/12.
//  Copyright (c) 2012 FX Palo Alto Lab. Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Faunus.h"
#import "Wallet.h"

int main(int argc, const char * argv[]) {
#pragma unused(argc,argv)

	@autoreleasepool {
	    Faunus *fn = [[Faunus alloc] init];

		NSString *nm = [fn createName:@"streamer" publicP:YES];

		NSMutableArray *names = [fn browseLocal:@"streamer"];
		NSLog(@"Found: %ld streamers", [names count]);

		for (NSString *name in names) {
			if ([name isEqualToString:nm]) {
				NSLog(@"Our name was successfully registered and listed: %@", name);
				break;
			}
		}

		if ([fn addAttr:@"IPv4" andValue:@"127.0.0.1" forName:nm] == NO)
			NSLog(@"Add capability 'IPv4' failed");

		if ([fn addAttr:@"port" andValue:@"12345" forName:nm] == NO)
			NSLog(@"Add capability 'port' failed");

		if ([fn addAttr:@"description" andValue:@"Faunus Test program" forName:nm] == NO)
			NSLog(@"Add capability 'description' failed");

		NSMutableArray *attrs = [fn listAttrs:nm];
		NSLog(@"There are %ld attributes for my name", [attrs count]);

		for (NSString *key in attrs) {
			NSString *val = [fn getAttr:key forName:nm];

			NSLog(@"Key=%@ Value=%@", key, val);
		}

		if ([fn delAttr:@"port" forName:nm] == NO)
			NSLog(@"DELATTR: failed");
		else
			NSLog(@"DELATTR: succeeded");

		attrs = [fn listAttrs:nm];
		NSLog(@"Now there are %ld attributes for my name", [attrs count]);

		for (NSString *key in attrs) {
			NSString *val = [fn getAttr:key forName:nm];

			NSLog(@"Key=%@ Value=%@", key, val);
		}

		if ([fn addChild:[fn createName:@"streamer" publicP:YES] forName:nm] == NO)
			NSLog(@"Add child failed");

		NSMutableArray *children = [fn listChildren:nm];
		NSLog(@"%ld children - %@", [children count], children);

		if ([fn delChild:[children objectAtIndex:0] forName:nm] == NO)
			NSLog(@"Delete child failed");

		children = [fn listChildren:nm];
		NSLog(@"%ld children - %@", [children count], children);
			// [fn addChild:nm2 forName:nm1];

		Wallet *wl = [[Wallet alloc] init];
		NSData *data = [wl getData];

		if ([fn mergeToWallet:data] == NO)
			NSLog(@"Merging wallet failed");

		if ([fn rememberName:@"SURENDAR" forType:@"streamer"] == NO)
			NSLog(@"Postit remember failed");

		NSMutableArray *postitNames = [fn listNames:@"streamer"];
		NSLog(@"Remembered: %ld items - %@", [postitNames count], postitNames);

		if ([fn forgetName:@"SURENDAR" forType:@"streamer"] == NO)
			NSLog(@"Postit forget failed");

		Capabilities *cap = [[Capabilities alloc] init];
		[cap setNm:nm];
			// [cap setKey:@"IPv4"];
		[cap setOperation:@"write"];

		Capabilities *cloned = [fn cloneCapability:cap];
		if (cloned == nil)
			NSLog(@"Cloning failed");
		else
			NSLog(@"Cloned capability is %@", cloned);

	}
    return 0;
}

