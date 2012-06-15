//
//  main.m
//  NameServer
//
//  Created by Surendar Chandra on 6/7/12.
//  Copyright (c) 2012 FX Palo Alto Laboratory Inc. All rights reserved.
//
#import "NameServer.h"

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		NameServer *nameServer = [[NameServer alloc] init];

		[nameServer start];
		
		[[NSRunLoop currentRunLoop] run];
	}
    return 0;
}

