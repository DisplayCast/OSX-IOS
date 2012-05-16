// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

@interface MenuEntry : NSObject {
	NSString *sessID;
}

- (NSString *)name;

- (id)initWithNS:(NSNetService *)nse andMenuItem: (NSMenuItem *)me;
- (void)updateNS:(NSNetService *)ns;
- (void)removeEntry:(NSMenu *)menu;

@property (nonatomic, retain) NSNetService *ns;
@property (nonatomic, retain) NSMenuItem *menuItem;
@end
