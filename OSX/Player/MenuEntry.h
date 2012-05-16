// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

@interface MenuEntry : NSObject 

- (id)initWithNS:(NSNetService *)nse andMenuItem: (NSMenuItem *)me;
- (NSString *)name;
- (void)updateNS:(NSNetService *)ns;
- (void)removeEntry:(NSMenu *)menu;

@property (nonatomic, retain) NSNetService *ns;
@property (nonatomic, retain) NSMenuItem *menuItem;
@end
