// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "MenuEntry.h"

	// Functions to establish the link between a menu entry and its corresponding NSService entry
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
    }
    
    return self;
}

- (void)updateNS:(NSNetService *)nse {
	NSDictionary *myKeys = [NSNetService dictionaryFromTXTRecordData:[nse TXTRecordData]];
	NSData *data = [myKeys objectForKey:@"name"];
	NSString *fullName = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	
	[menuItem setTitle:fullName];
	
	[ns stop];
	ns = nse;
}

- (void)removeEntry:(NSMenu *)menu {
	[ns stop];

	[menu removeItem:menuItem];
	[menuItem release];
	menuItem = nil;
}
@end
