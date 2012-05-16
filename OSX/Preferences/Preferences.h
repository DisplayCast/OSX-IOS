// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <PreferencePanes/PreferencePanes.h>

@interface Preferences : NSPreferencePane {
	IBOutlet NSView *preferenceView;
	IBOutlet NSTextField *streamerName, *playerName, *archiverName;
	IBOutlet NSButton *discloseLocation;
	
	NSString *myUniqueID;
}

- (void)mainViewDidLoad;

- (IBAction)changestreamernameAction:(id)sender;
- (IBAction)changeplayernameAction:(id)sender;
- (IBAction)changearchivernameAction:(id)sender;
- (IBAction)changelocationdisclosureAction:(id)sender;
@end
