// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>
#import <CoreFoundation/CFSocket.h>

#include <sys/types.h>  /* for type definitions */
#include <sys/socket.h> /* for socket API calls */
#include <netinet/in.h> /* for address structs */
#include <arpa/inet.h>  /* for sockaddr_in */
#include <sys/types.h>
#include <sys/time.h>

#import "MenuEntry.h"
#import "StreamerAppDelegate.h"
#import "Streamer.h"
#import "Globals.h"

#ifdef USE_XMPP
#import "XMPPFramework.h"
#import "TURNSocket.h"
#endif /* USE_XMPP */

@implementation StreamerAppDelegate
NSMenu *projectMenu, *archiveMenu;
Streamer *stm = nil;

@synthesize projectMenu;
@synthesize archiveMenu;
@synthesize playerBrowser = _playerBrowser;
@synthesize archiveBrowser = _archiveBrowser;

#ifdef USE_XMPP
@synthesize xmppStream;
@synthesize xmppReconnect;
@synthesize xmppRoster;
@synthesize xmppPresence;
@synthesize xmppRosterStorage;
@synthesize xmppCapabilities;
@synthesize xmppCapabilitiesStorage;
@synthesize xmppPing;
@synthesize xmppRoom;

- sendMessage:(id)sender;
#endif /* USE_XMPP */


- (IBAction)aboutAction:(id)sender {
	[NSApp activateIgnoringOtherApps:YES];
    
    [[NSApplication sharedApplication] orderFrontStandardAboutPanel:sender];
}

- (IBAction)setPreferences:(id)sender {
#pragma unused(sender)
	
	NSAppleScript *a = [[NSAppleScript alloc] initWithSource:PREFERENCES_APPSCRIPT];
	[a executeAndReturnError:nil];
	[a release];
}

- (IBAction)commitPreferences:(id)sender {
#pragma unused(sender)
	[NSApp activateIgnoringOtherApps:YES];
	
	NSLog(@"Preferences set at: %@", [name value]); 
}

#pragma mark -
#pragma mark *Manipulate menuentries for each player/archiver
	// Adds a new menu item for this service.
- (void) addEntry:(NSNetService *)ns andArray:(NSMutableArray *)array andMenu:(NSMenu*) menu {
	unsigned long count = [array count];
	for (unsigned int i=0; i < count; i++) {
		MenuEntry *object = [array objectAtIndex:i];
		
		if ([[ns name] isEqualToString:[object name]]) {
			[object updateNS:ns];
			
			return;
		}
	}

	NSDictionary *myKeys = [NSNetService dictionaryFromTXTRecordData:[ns TXTRecordData]];
	NSString	 *fullName = [[[NSString alloc] initWithData:[myKeys objectForKey:@"name"] encoding:NSUTF8StringEncoding] autorelease];
	NSMenuItem *item = [[[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:fullName action:@selector(projectAction:) keyEquivalent:@""] autorelease];
	
		// Use MenuEntry to keep track of the NSNetService. On user click, we need the NSNetService to know where the Player is
	MenuEntry *me = [[[MenuEntry alloc] initWithNS:ns andMenuItem:item] autorelease];
	
	[item setTarget:me];
	[menu addItem:item];
	
	[array addObject:me];
}

- (void) delEntry:(NSNetService *)ns andArray:(NSMutableArray *)array andMenu:(NSMenu*) menu {
	unsigned long count = [array count];
	for (unsigned int i=0; i < count; i++) {
		MenuEntry *object = [array objectAtIndex:i];
		
		if ([[ns name] isEqualToString:[object name]]) {
			[object removeEntry:menu];
			[array removeObject:object];
			
			return;
		}
	}

	NSLog(@"DEBUG: Trying to delete non-existent entry");
}

#pragma mark -
#pragma mark *NS Browsing
NSMutableArray *player = nil, *archiver = nil;

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
#pragma unused(moreComing)
#pragma unused(aNetServiceBrowser)

    [aNetService retain];
    [aNetService setDelegate:self];
	
	[aNetService scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [aNetService resolveWithTimeout:5.0];
}

- (void)netServiceDidResolveAddress:(NSNetService *)ns {
    [ns startMonitoring];   // For txt record updates
}

- (void)netService:(NSNetService *)ns didNotResolve:(NSDictionary *)errorDict {
#pragma unused(errorDict)
    [ns stop];
}

- (void)netService:(NSNetService *)ns didUpdateTXTRecordData:(NSData *)data {
#pragma unused(data)
	
	if ([[ns type] isEqualToString:PLAYER])
		[self addEntry:ns andArray:player andMenu:projectMenu];
	else
		[self addEntry:ns andArray:archiver andMenu:archiveMenu];
}


- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
#pragma unused(aNetServiceBrowser)
#pragma unused(moreComing)
	if ([[aNetService type] isEqualToString:PLAYER])
		[self delEntry:aNetService andArray:player andMenu:projectMenu];
	else
		[self delEntry:aNetService andArray:archiver andMenu:archiveMenu];

	[aNetService stop];
}

- (void) awakeFromNib {
	/*
	statusMenu = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
	
	NSString *path = [[NSBundle mainBundle] pathForResource:@"icon" ofType:@"tiff"];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile: path ];

	[statusItem setMenu:statusMenu];
	[statusItem setHighlightMode:YES];
	[statusItem setImage:image];
	 */
}

#ifdef USE_XMPP
	//XMPPStream *xmppStream;

- (void)xmppStream:(XMPPStream *)sender didRegisterModule:(id)module {
#pragma unused(sender)
#pragma unused(module)
	NSLog(@"didRegisterModule:");
}


- (void)xmppStreamDidConnect:(XMPPStream *)sender {
#pragma unused(sender)
    [xmppStream authenticateWithPassword:@"passwd" error:NULL];
}

- (void)xmppStream:(XMPPStream *)sender didReceiveError:(id)error {
#pragma unused(sender)
	NSLog(@"didReceiveError: %@", error);
}

- (void)xmppStream:(XMPPStream *)sender didNotAuthenticate:(NSXMLElement *)error {
#pragma unused(sender)
	NSLog(@"didNotAuthenticate: %@", error);
}

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender {
	NSLog(@"didAuthenticate: %@", sender);

	xmppRoom = [[XMPPRoom alloc] initWithRoomName:@"wtf@conference.displaycast.fxpal.net/wtf" nickName:@"Surendar's Mac Mini" dispatchQueue:dispatch_get_main_queue()];
	[xmppRoom activate:xmppStream];
	[xmppRoom createOrJoinRoom];
	
		// Activate xmpp modules
	[xmppReconnect activate:xmppStream];
	[xmppRoster activate:xmppStream];
	[xmppCapabilities activate:xmppStream];
	[xmppPing activate:xmppStream];
	[xmppTime activate:xmppStream];
	
	[xmppReconnect addDelegate:self delegateQueue:dispatch_get_main_queue()];
	[xmppCapabilities addDelegate:self delegateQueue:dispatch_get_main_queue()];
	[xmppPing addDelegate:self delegateQueue:dispatch_get_main_queue()];
	[xmppTime addDelegate:self delegateQueue:dispatch_get_main_queue()];

	NSXMLElement *presence = [NSXMLElement elementWithName:@"presence"];
		// [presence addAttributeWithName:@"to" stringValue:[jid bare]];
		// [presence addAttributeWithName:@"type" stringValue:@"subscribe"];
	
		// [presence addAttributeWithName:@"type" stringValue:@"subscribe"];
	
		// XMPPCapabilitiesCoreDataStorage *xmppcorest = [[XMPPCapabilitiesCoreDataStorage alloc] init];
		// [xmppcorest insertValue:@"audio" inPropertyWithKey:@"ext"];
		// XMPPCapabilities *xmppcap = [[XMPPCapabilities alloc] initWithCapabilitiesStorage:xmppcorest dispatchQueue:dispatch_get_main_queue()];
	
		// [presence addAttribute:xmppcap];
	
	[[self xmppStream] sendElement:presence];
}

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq {
		// NSLog(@"didReceiveID: %@", iq);

	if ([TURNSocket isNewStartTURNRequest:iq]) {
		NSLog(@"isNewStartTURNRequest");
		
		TURNSocket *turnSocket = [[TURNSocket alloc] initWithStream:sender incomingTURNRequest:iq];
		
		[turnSockets addObject:turnSocket];
		
		[turnSocket startWithDelegate:self delegateQueue:dispatch_get_main_queue()];
		[turnSocket release];
		
		return YES;
	}
	
	return NO;
}

- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence {
#pragma unused(sender)
	NSLog(@"DidreceivePresence: %@", presence);
}

- (void)turnSocket:(TURNSocket *)sender didSucceed:(GCDAsyncSocket *)socket {
#pragma unused(socket)
	NSLog(@"TURN Connection succeeded!");
	NSLog(@"You now have a socket that you can use to send/receive data to/from the other person.");
	
		// Now retain and use the socket.
	
	[turnSockets removeObject:sender];
}

- (void)turnSocketDidFail:(TURNSocket *)sender {
	NSLog(@"TURN Connection failed!");
	
	[turnSockets removeObject:sender];
}

- xmppCapabilities:(XMPPCapabilities *)capabilities collectingMyCapabilities:(NSXMLElement *)query {
#pragma unused(capabilities)
	NSLog(@"Adding my capabilities");
	
	[query addAttributeWithName:@"streamer" stringValue:@"1000"];
	return nil;
}

- (BOOL)xmppReconnect:(XMPPReconnect *)sender shouldAttemptAutoReconnect:(SCNetworkReachabilityFlags)reachabilityFlags {
#pragma unused(sender)
#pragma unused(reachabilityFlags)
	NSLog(@"---------- xmppReconnect:shouldAttemptAutoReconnect: ----------");
	
	return YES;
}

- (void)xmppCapabilities:(XMPPCapabilities *)sender didDiscoverCapabilities:(NSXMLElement *)caps forJID:(XMPPJID *)jid {
#pragma unused(sender)
	NSLog(@"---------- xmppCapabilities:didDiscoverCapabilities:forJID: ----------");
	NSLog(@"jid: %@", jid);
	NSLog(@"capabilities:\n%@",
				 [caps XMLStringWithOptions:(NSXMLNodeCompactEmptyElement | NSXMLNodePrettyPrint)]);
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message {
#pragma unused(sender)
	NSLog(@"DEBUG: Message received: %@", message);
	if([message isChatMessageWithBody]) {
		NSXMLElement *body = [message elementForName:@"body"];
		NSLog(@"Received : %@", body);
		
		[self sendMessage:[message from]];
	} 
}

- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error {
#pragma unused(sender)
#pragma unused(error)
	NSLog(@"Stream disconnected");
}

- sendMessage:(id)sender {
	NSXMLElement *body = [NSXMLElement elementWithName:@"body"];
		// [body setStringValue:@"My secret valentine"];
	NSString *path = [[NSBundle mainBundle] pathForResource:@"icon" ofType:@"tiff"];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile: path ];
	NSData *data = [image TIFFRepresentation];
	[body setObjectValue:data];
		
	NSXMLElement *message = [NSXMLElement elementWithName:@"message"];
	[message addAttributeWithName:@"type" stringValue:@"chat"];
	[message addAttributeWithName:@"to" stringValue:[sender bare]];
	[message addChild:body];
		
	UInt64 before = [xmppStream numberOfBytesSent];
	[xmppStream sendElement:message];
	
	NSLog(@"Size of data: %lu size of body: %llu", [data length], [xmppStream numberOfBytesSent] - before);
}

- (void)xmppRoomDidCreate:(XMPPRoom *)sender {
	NSLog(@"Room created: %@", sender);
}

- (void)xmppRoomDidEnter:(XMPPRoom *)sender {
#pragma unused(sender)
	NSLog(@"Did Enter");
}

- (void)xmppRoomDidLeave:(XMPPRoom *)sender {
#pragma unused(sender)
	NSLog(@"Did Leave");
}

- (void)xmppRoom:(XMPPRoom *)sender didReceiveMessage:(XMPPMessage *)message fromNick:(NSString *)nick {
#pragma unused(sender)
	NSLog(@"Room - Did Receive Message %@ from %@", message, nick);
}
- (void)xmppRoom:(XMPPRoom *)sender didChangeOccupants:(NSDictionary *)occupants {
	NSLog(@"Room - changed occupants: %@ for %@", sender, occupants);
}
#endif /* USE_XMPP */

#ifdef USE_BLUETOOTH
IOBluetoothDeviceInquiry *btd = nil;
- (void) deviceInquiryComplete:(IOBluetoothDeviceInquiry *)sender error:(IOReturn)error aborted:(BOOL)aborted {
#pragma unused(sender)
#pragma unused(error)
#pragma unused(aborted)
	IOBluetoothDevice *device;
	NSString *nearbyDeviceNames = @"";
	MenuEntry *object;
	NSMenuItem *menu;
	NSDictionary *attributes;
	NSAttributedString *as;
	
		// First, reset all old entries
	for (unsigned int i=0; i < [player count]; i++) {
		object = [player objectAtIndex:i];
		menu = [object menuItem];
		
		attributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor blackColor], NSForegroundColorAttributeName, [NSFont systemFontOfSize: [NSFont systemFontSize]], NSFontAttributeName, nil];
		as = [[[NSAttributedString alloc] initWithString:[menu title] attributes:attributes] autorelease];
		[menu setAttributedTitle:as];
		[menu setToolTip:nil];
	}
		
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor blueColor], NSForegroundColorAttributeName, [NSFont boldSystemFontOfSize: 0], NSFontAttributeName, nil];
	for (device in [sender foundDevices]) {
		NSString *devStr = [device addressString];
		
		for (unsigned int i=0; i < [player count]; i++) {
			object = [player objectAtIndex:i];
			NSNetService *ns = [object ns];
			
			NSDictionary *keys = [NSNetService dictionaryFromTXTRecordData:[ns TXTRecordData]];
			NSData *data = [keys objectForKey:@"bluetooth"];
			if (data == nil)
				continue;
			
			NSString *btName = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
			
			if ([btName isEqualToString:devStr]) {
				nearbyDeviceNames = [nearbyDeviceNames stringByAppendingFormat:@" %@", [ns name]];
				
				menu = [object menuItem];
				as = [[[NSAttributedString alloc] initWithString:[menu title] attributes:attributes] autorelease];
				[menu setAttributedTitle:as];
				[menu setToolTip:@"Nearby"];
			}
		}
	}
		// NSLog(@"Found devices: %@", [sender foundDevices]);
	[stm nearbyDevices:nearbyDeviceNames];
		// [btd clearFoundDevices];
	
	[self performSelector:@selector(bluetoothScan) withObject:nil afterDelay:120.0];
		// [btd start];
}

- (void) deviceInquiryDeviceFound:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)device {
#pragma unused(sender)
#pragma unused(device)
		// NSLog(@"Found BT: %@", [device addressString]);
	
}

- (void) bluetoothScan {
	if ([btd start] != kIOReturnSuccess) 
		NSLog(@"Start failed");
	
	/* dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    double delayInSeconds = 120.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, q_background, ^(void){
        [self bluetoothScan];
    });
	 */
}

#endif /* USE_BLUETOOTH */

void catchallExceptionHandler(NSException *exception) {
#pragma unused(exception)
	NSAppleScript *a = [[NSAppleScript alloc] initWithSource:@"tell application \"Streamer\"\nactivate\nend tell"];
	[a executeAndReturnError:nil];
	[a release];
	exit(1);
}

#pragma mark -
#pragma mark *Main function
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
#pragma unused(aNotification)
	
	NSSetUncaughtExceptionHandler(&catchallExceptionHandler);
	@autoreleasepool {
			// NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		stm = [[Streamer alloc] init];
		
		CGRegisterScreenRefreshCallback(MyScreenRefreshCallback, stm);
		
			// Works in 10.7+ to remove from the Dock
		ProcessSerialNumber psn = {0, kCurrentProcess};
		TransformProcessType(&psn, kProcessTransformToUIElementApplication);
			// TransformProcessType(&psn, kProcessTransformToForegroundApplication);
		
		player = [[NSMutableArray arrayWithCapacity:10] retain];
		archiver = [[NSMutableArray arrayWithCapacity:10] retain];
		
			// XMPP STUFF
#ifdef USE_XMPP
		turnSockets = [[NSMutableArray alloc] init];
		
		xmppStream = [[XMPPStream alloc] init];
		xmppReconnect = [[XMPPReconnect alloc] init];
		xmppRosterStorage = [[XMPPRosterMemoryStorage alloc] init];
		xmppRoster = [[XMPPRoster alloc] initWithRosterStorage:xmppRosterStorage];
		xmppCapabilitiesStorage = [[XMPPCapabilitiesCoreDataStorage alloc] init];
		xmppCapabilities = [[XMPPCapabilities alloc] initWithCapabilitiesStorage:xmppCapabilitiesStorage];
		xmppCapabilities.autoFetchHashedCapabilities = YES;
		xmppCapabilities.autoFetchNonHashedCapabilities = NO;
		xmppPing = [[XMPPPing alloc] init];
		xmppTime = [[XMPPTime alloc] init];
		xmppPresence = [[XMPPPresence alloc] init];
		
			// NSString *myJID = [[NSString alloc] initWithFormat:@"chandra@palcomm/displaycast:%@", [stm streamerID]];
		NSString *myJID = [[NSString alloc] initWithFormat:@"chandra@displaycast.fxpal.net/displaycast:%@", [stm streamerID]];
		xmppStream.myJID = [XMPPJID jidWithString:myJID];
		xmppStream.hostName = @"displaycast.fxpal.net";
		
		[xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];
		
		NSError *error = nil;
		if (![xmppStream connect:&error])
			NSLog(@"FATAL: XMPP connect failed: %@", error);
#endif /* USE_XMPP */
			// ====================================
		
#if MANUAL
			// Using the xib file is always better
		NSZone *zone = [NSMenu menuZone];
		NSMenu *menu = [[[NSMenu allocWithZone:zone] init] autorelease];
		NSMenuItem *item;
		
		projectMenu = [[[NSMenu allocWithZone:[NSMenu menuZone]] init] autorelease];
		
		item = [menu addItemWithTitle:@"ProjectMe" action:@selector(projectAction:) keyEquivalent:@""];
		[item setTarget:self];
		item = [menu addItemWithTitle:@"ArchiveMe" action:@selector(archiveAction:) keyEquivalent:@""];
		[item setTarget:self];
		[menu insertItem:[NSMenuItem separatorItem] atIndex:2];
		
		item = [menu addItemWithTitle:@"Desktop to stream" action:@selector(chooseDesktopAction:) keyEquivalent:@""];
		[item setTarget:self];
		item = [menu addItemWithTitle:@"Change Name" action:@selector(changeNameAction:) keyEquivalent:@""];
		[item setTarget:self];
		[menu insertItem:[NSMenuItem separatorItem] atIndex:5];
		
		item = [menu addItemWithTitle:@"About..." action:@selector(aboutAction:) keyEquivalent:@""];
		[item setTarget:self];
		[menu insertItem:[NSMenuItem separatorItem] atIndex:7];
		
		item = [menu addItemWithTitle:@"Quit Streamer" action:@selector(quitAction:) keyEquivalent:@""];
		[item setTarget:self];
#endif /* MANUAL */
		
		NSString *path = [[NSBundle mainBundle] pathForResource:@"icon" ofType:@"tiff"];
		NSImage *image = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
		
		trayItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
		[trayItem setMenu:statusMenu];
		[trayItem setHighlightMode:YES];
		[trayItem setImage: image];
		
			// Start the Bonjour browser.
		_playerBrowser = [[NSNetServiceBrowser alloc] init];
		[_playerBrowser setDelegate:self];
		[_playerBrowser scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
		[_playerBrowser searchForServicesOfType:PLAYER inDomain:BONJOUR_DOMAIN];
		
		_archiveBrowser = [[NSNetServiceBrowser alloc] init];
		[_archiveBrowser setDelegate:self];
		[_archiveBrowser scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
		[_archiveBrowser searchForServicesOfType:ARCHIVER inDomain:BONJOUR_DOMAIN];
		
#ifdef USE_BLUETOOTH
		btd = [[IOBluetoothDeviceInquiry alloc] initWithDelegate:self];
		[btd setSearchCriteria:kBluetoothServiceClassMajorAny majorDeviceClass:kBluetoothDeviceClassMajorComputer minorDeviceClass:kBluetoothDeviceClassMinorAny];
		[btd start];
		
			// NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
			// NSTimer *timer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(bluetoothScan) userInfo:nil repeats:YES] retain];
			// [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
			// [self bluetoothScan];
			// dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
			// dispatch_async(q_background, ^{
			// [self bluetoothScan];
			// });
#endif /* BLUETOOTH */
		
			// [pool drain];
	}
}

- (void)dealloc {
	[trayItem release];
	[super dealloc];
}

@end
