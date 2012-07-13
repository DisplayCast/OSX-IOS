// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Cocoa/Cocoa.h>

#ifdef USE_XMPP
#import "XMPPFramework.h"
#import "XMPPRoster.h"
#import "XMPPRosterMemoryStorage.h"
#import "XMPPReconnect.h"
#import "XMPPCapabilitiesCoreDataStorage.h"
#import "XMPPPing.h"
#import "XMPPTime.h"
#import "XMPPRoom.h"
#endif /* USE_XMPP */

@interface StreamerAppDelegate : NSObject <NSApplicationDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate, NSMenuDelegate> {
	IBOutlet NSMenu *statusMenu;
	
	NSTextField *name;
	NSStatusItem *trayItem;
	NSArray *roster;
	
#ifdef USE_XMPP
	XMPPStream *xmppStream;
	XMPPReconnect *xmppReconnect;
	XMPPRoster *xmppRoster;
	XMPPPresence *xmppPresence;
	XMPPRosterMemoryStorage *xmppRosterStorage;
	XMPPCapabilities *xmppCapabilities;
	XMPPCapabilitiesCoreDataStorage *xmppCapabilitiesStorage;
	XMPPPing *xmppPing;
	XMPPTime *xmppTime;
	XMPPRoom *xmppRoom;
	
	NSMutableArray *turnSockets;
#endif /* USE_XMPP */
	
	NSNetServiceBrowser * _playerBrowser;
	NSNetServiceBrowser * _archiveBrowser;
@private
		// NSWindow *window;
}

	// @property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSMenu *projectMenu;
@property (assign) IBOutlet NSMenu *archiveMenu;

@property (nonatomic, retain, readwrite) NSNetServiceBrowser *  playerBrowser;
@property (nonatomic, retain, readwrite) NSNetServiceBrowser *  archiveBrowser;

#ifdef USE_XMPP
@property (nonatomic, readonly) XMPPStream *xmppStream;
@property (nonatomic, readonly) XMPPReconnect *xmppReconnect;
@property (nonatomic, readonly) XMPPRoster *xmppRoster;
@property (nonatomic, readonly) XMPPPresence *xmppPresence;
@property (nonatomic, readonly) XMPPRosterMemoryStorage *xmppRosterStorage;
@property (nonatomic, readonly) XMPPCapabilities *xmppCapabilities;
@property (nonatomic, readonly) XMPPCapabilitiesCoreDataStorage *xmppCapabilitiesStorage;
@property (nonatomic, readonly) XMPPPing *xmppPing;
@property (nonatomic, readonly) XMPPRoom *xmppRoom;
#endif /* USE_XMPP */

void catchallExceptionHandler(NSException *exception);

#ifdef USE_BLUETOOTH
- (void) bluetoothScan;
#endif /* USE_BLUETOOTH */

@end
