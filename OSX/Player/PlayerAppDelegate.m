// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <CoreFoundation/CFSocket.h>

#import "PlayerAppDelegate.h"
#import "Globals.h"

#ifdef USE_BLUETOOTH
#import <IOBluetooth/IOBluetooth.h>
#import <IOBluetooth/IOBluetoothUserLib.h>
#import <IOBluetooth/IOBluetoothUtilities.h>
#import <IOBluetooth/objc/IOBluetoothDeviceInquiry.h>
#import <IOBluetooth/objc/IOBluetoothDevice.h>
#import <IOBluetooth/objc/IOBluetoothHostController.h>
#endif /* USE_BLUETOOTH */

#import "GetUniqueID.h"

#include <sys/types.h>  /* for type definitions */
#include <sys/socket.h> /* for socket API calls */
#include <netinet/in.h> /* for address structs */
#include <arpa/inet.h>  /* for sockaddr_in */
#include <sys/time.h>
#include <zlib.h>

@interface PlayerAppDelegate () <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSWindowDelegate>

@property (nonatomic, retain, readwrite) NSNetServiceBrowser *  browser;
@property (nonatomic, retain, readonly ) NSMutableSet *         pendingServicesToAdd;
@property (nonatomic, retain, readonly ) NSMutableSet *         pendingServicesToRemove;
@property (nonatomic, copy,   readwrite) NSString *             serviceName;
@property (nonatomic, copy,   readonly ) NSString *             defaultServiceName;

// forward declarations
- (void)receiveFromService:(NSNetService *)service;

void drawWin(UInt32 *winData, int width, int height, int x, int y, int w, int h, UInt32 *buf);
void displayWin(NSImageView *player, int width, int height, int maskX, int maskY, int maskWidth, int maskHeight, UInt32 *buf);

void receiveCmdData(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

void catchallExceptionHandler(NSException *exception);
@end

@implementation PlayerAppDelegate
@synthesize streamMenu;			// Used for taskbar style
@synthesize chooserWindow;		// Use when window style chooser is used
@synthesize sortDescriptors;
@synthesize servicesArray = _servicesArray;
@synthesize browser = _browser;

// Generating the Windows from the XIB file.
@synthesize rw0;
@synthesize rw1;
@synthesize rw2;
@synthesize rw3;
@synthesize rw4;
@synthesize rw5;
@synthesize rw6;
@synthesize rw7;
@synthesize rw8;
@synthesize rw9;

SInt32 OSversion = 0;			// Special processing for 10.7+

NSNetService *netService;		// Register ourselves

// Using interface builder to create windows
#ifdef PLAYER_USE_XIB
#define NUM_SESSIONS 10			// Static number of windows from the XIB file
NSWindow *windows[NUM_SESSIONS];
NSImageView *imageviewers[NUM_SESSIONS];

NSNetService *activeNSSessions[NUM_SESSIONS];
bool		 stopSession[NUM_SESSIONS];			// Cooperative session kill
#endif /* PLAYER_USE_XIB */

#ifdef PLAYER_TASKBAR
NSMutableArray *streamer = nil;
#endif /* PLAYER_TASKBAR */

- (void)dealloc {
	[trayItem release];
    [super dealloc];
}

#pragma mark -
#pragma mark Remote control functionality

// Main processing function for remote control commands
void receiveCmdData(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
#pragma unused(type)
    PlayerAppDelegate *obj = (PlayerAppDelegate *)info;
    assert([obj isKindOfClass:[PlayerAppDelegate class]]);
    NSString *result = PlayerCommandUnknownError;                   // Generic status
    
    NSString *command = [[[NSString alloc] initWithData:(NSData *)data encoding:NSUTF8StringEncoding /* NSASCIIStringEncoding */] autorelease];
    NSArray *array = [command componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *cmd = [array objectAtIndex:0];
    
    NSLog(@"Command: %@", command);
    // NSLog(@"Array: %@", array);
    if ([cmd isEqualToString:@"SHOW"]) {
		if ([array count] < 2) {
			result = PlayerCommandSyntaxErrorShow;
		} else {
			NSString *strm = [array objectAtIndex:1];
            
            // Search all nsSessions - dependig on whether we are using the Choosewidow or the Taskbar interface
			boolean_t done = false;
#ifdef PLAYER_TASKBAR
				// MenuEntry *entry = nil;
				// for (int i=([streamer count]-1); i >= 0; i++) {
				// entry = [streamer objectAtIndex:i];
				
			for (MenuEntry *entry in streamer) {
				if ([[[entry ns] name] isEqual:strm]) {
                    // First check whether this is a duplicate session request
					for (int indx = 0; indx < NUM_SESSIONS; indx++) {
						if (activeNSSessions[indx] == nil)
							continue;
						
						if ([[activeNSSessions[indx] name] isEqualToString:[[entry ns] name]]) {
							[windows[indx] orderFrontRegardless];
                            
#ifdef PLAYER_LION_FS
                            if (([[array objectAtIndex:2] isEqualToString:@"FULLSCREEN"]) && (OSversion >= 0x1070))
                                if (([windows[indx] styleMask] & NSFullScreenWindowMask) != NSFullScreenWindowMask)
                                    [windows[indx] toggleFullScreen:nil];
#endif /* PLAYER_LION_FS */
							result = [[[NSString alloc] initWithFormat: @"%lu", [windows[indx] hash]] autorelease];
							done = true;
							
							break;
						}
					}
					
					if (!done) {
                        // Next see if there is space to create a new session
						for (int indx = 0; indx < NUM_SESSIONS; indx++) {
							if (activeNSSessions[indx] == nil) {
								activeNSSessions[indx] = [entry ns];
								[[entry menuItem] setState:NSOnState];
								[NSThread detachNewThreadSelector:@selector(receiveFromService:) toTarget:obj withObject:[entry ns]];
								
								result = [[[NSString alloc] initWithFormat: @"%lu", [windows[indx] hash]] autorelease];
								done = true;
								break;
							}
						}
					}
					
					if (done == false) {
						NSLog(@"FATAL: Too many sessions");
						result = PlayerCommandTooManySessions;
						
						done = true;
					}
					break;
				}
			}
#else
			for (PlayerListing *pl in obj.servicesArray.content) {
				NSNetService *plns = [pl ns];
				NSString *plName = [plns name];
				
				if ([plName isEqualToString:strm]) {
                    // First check whether this is a duplicate
					for (int indx = 0; indx < NUM_SESSIONS; indx++) {
						NSNetService *ns = activeNSSessions[indx];
						
						if (ns == nil)
							continue;
						
						if ([[ns name] isEqualToString:plName]) {
							NSLog(@"DEBUG: Session already active, bringing to front");
							
							[windows[indx] orderFrontRegardless];
							
#ifdef PLAYER_LION_FS
                            if (([[array objectAtIndex:2] isEqualToString:@"FULLSCREEN"]) && (OSversion >= 0x1070))
                                if (([windows[indx] styleMask] & NSFullScreenWindowMask) != NSFullScreenWindowMask)
                                    [windows[indx] toggleFullScreen:nil];
#endif /* PLAYER_LION_FS */
                            
							result = [[[NSString alloc] initWithFormat: @"%lu", [windows[indx] hash]] autorelease];
							done = true;
							
							break;
						}
					}
					
					if (done == false) {
						NSLog(@"DEBUG: Starting a new session: %@", strm);
						for (int indx = 0; indx < NUM_SESSIONS; indx++) {
							if (activeNSSessions[indx] == nil) {
								activeNSSessions[indx] = plns;
								
								[NSThread detachNewThreadSelector:@selector(receiveFromService:) toTarget:obj withObject:plns];
                                
								// result = [[[NSString alloc] initWithFormat: @"%lu", [windows[indx] hash]] autorelease];
                                result = [NSString stringWithFormat: @"%lu", [windows[indx] hash]];
                                done = true;
                                
                                break;
                            }
                        }
                        if (done == false) {
                            NSLog(@"FATAL: Too many sessions");
                            result = PlayerCommandTooManySessions;
                            
                            done = true;
                        }
                    }
                }
            }
#endif /* PLAYER_TASKBAR */
            
            if (done == false) {
                NSLog(@"DEBUG: Unknown stream: %@", strm);
                result = PlayerCommandStreamerNotFound;
            }
        }
    }
    
    if ([cmd isEqualToString:@"CLOSE"]) {
        if ([array count] != 2) {
            result = PlayerCommandSyntaxErrorClose;
        } else {
            NSString *strm = [array objectAtIndex:1];
            NSUInteger hash = [strm integerValue];
            
            for (int indx = 0; indx < NUM_SESSIONS; indx++) {
                if ([windows[indx] hash] == hash) {
                    
                    stopSession[indx] = true;		// Schedule for this session to be closed gracefully
                    result = PlayerCommandSuccess;
                    
                    break;
                }
            }
        }
    }
    
    if ([cmd isEqualToString:@"CLOSEALL"]) {
        for (int indx = 0; indx < NUM_SESSIONS; indx++) 
            stopSession[indx] = true;
        result = PlayerCommandSuccess;
    }
    
    // Iconify a particular session
    if ([cmd isEqualToString:@"ICON"]) {
        if ([array count] != 2) {
            result = PlayerCommandSyntaxErrorIcon;
        } else {
            NSString *strm = [array objectAtIndex:1];
            NSUInteger hash = [strm integerValue];
            
            for (int indx = 0; indx < NUM_SESSIONS; indx++) {
                if ([windows[indx] hash] == hash) {
                    
                    [windows[indx] performZoom:obj];
                    
                    result = PlayerCommandSuccess;
                    break;
                }
            }
        }
    }
    
    if ([cmd isEqualToString:@"DICO"]) {
        if ([array count] != 2) {
            result = PlayerCommandSyntaxErrorDico;
        } else {
            NSString *strm = [array objectAtIndex:1];
            NSUInteger hash = [strm integerValue];
            
            for (int indx = 0; indx < NUM_SESSIONS; indx++) {
                if ([windows[indx] hash] == hash) {
                    [windows[indx] performMiniaturize:obj];
                    result = PlayerCommandSuccess;
                    
                    break;
                }
            }
        }
    }
    
    if ([cmd isEqualToString:@"MOVE"]) {
        if ([array count] != 3) {
            result = PlayerCommandSyntaxErrorMove;
        } else {
            NSString *strm = [array objectAtIndex:1];
            NSString *dimen = [array objectAtIndex:2];
            NSUInteger hash = [strm integerValue];
            NSArray *dimArray = [dimen componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"x"]];
            
            if ([dimArray count] == 4) {
                NSUInteger x = [[dimArray objectAtIndex:0] intValue], y = [[dimArray objectAtIndex:1] intValue], w = [[dimArray objectAtIndex:2] intValue], h = [[dimArray objectAtIndex:3] intValue];
                
                for (int indx = 0; indx < NUM_SESSIONS; indx++) {
                    if ([windows[indx] hash] == hash) {                
                        [windows[indx] setContentSize:NSMakeSize(w, h)];
                        [windows[indx] setFrameOrigin:NSMakePoint(x, y)];
                        [imageviewers[indx] setFrame:NSMakeRect(0.0, 0.0, w, h)];
                        
                        NSLog(@"Moved windows to: %lux%lu %lux%lu", x, y, w, h);
                        
                        result = PlayerCommandSuccess;
                        
                        break;
                    }
                }
            } else
                result = PlayerCommandSyntaxErrorMove;
        }
    }

	@try {
			// Send the result back to the client
		CFSocketSendData(s, address, (CFDataRef)[result dataUsingEncoding:NSASCIIStringEncoding], 0);
		
			// We only take one command in each session
		CFSocketInvalidate(s);
		CFRelease(s);
	} @catch (NSException *e) {
	}
}

// Listening. Now setup to call receivedCmdData whenever a client connects to us
static void ListeningSocketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
#pragma unused(type,address,s) 
    PlayerAppDelegate *obj = (PlayerAppDelegate *)info;
    assert([obj isKindOfClass:[PlayerAppDelegate class]]);
    
    CFSocketContext CTX = { 0, obj, NULL, NULL, NULL };
    
    CFSocketNativeHandle csock = *(CFSocketNativeHandle *)data;

		// Do not generate SIGPIPE signal. 
	int set = 1;
	setsockopt(csock, SOL_SOCKET, SO_NOSIGPIPE, (void *)&set, sizeof(int));
	
    CFSocketRef sn = CFSocketCreateWithNative(NULL, csock, kCFSocketDataCallBack, receiveCmdData, &CTX);
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, sn, 0);
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    
    CFRelease(source);
    CFRelease(sn);
}

#pragma mark -
#pragma mark Preferences actions
- (void) prefcallbackWithNotification:(NSNotification *)myNotification {
#pragma unused(myNotification)
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSString *myName = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
    
    [self setServiceName:myName];
}

- (IBAction)setPreferences:(id)sender {
#pragma unused(sender)
    
    NSAppleScript *a = [[NSAppleScript alloc] initWithSource:PREFERENCES_APPSCRIPT];
    [a executeAndReturnError:nil];
    [a release];
}

#pragma mark -
#pragma mark * Utility functions

- (IBAction)aboutAction:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    
    [[NSApplication sharedApplication] orderFrontStandardAboutPanel:sender];
}

// Default exception handler!!
void catchallExceptionHandler(NSException *exception) {
#pragma unused(exception)
    
    // Trying to use AppleScript to restart ourselves
    NSAppleScript *a = [[NSAppleScript alloc] initWithSource:@"tell application \"Player\"\nactivate\nend tell"];
    
    [a executeAndReturnError:nil];
    
    [a release];
    exit(1);
}

#pragma mark -
#pragma mark Basic initialization
- (in_port_t)createServerSocketWithAcceptCallBack:(CFSocketCallBack)callback {
	int fdForListening = socket(AF_INET6, SOCK_STREAM, 0);
	
	struct sockaddr_in6 serverAddress6;
	memset(&serverAddress6, 0, sizeof(serverAddress6));
	serverAddress6.sin6_family = AF_INET6;
	serverAddress6.sin6_port = 0;
	serverAddress6.sin6_len = sizeof(serverAddress6);
	bind(fdForListening, (const struct sockaddr *) &serverAddress6, sizeof(serverAddress6));
	
	listen(fdForListening, 1);
	
	CFSocketContext context = {0, self, NULL, NULL, NULL};
	CFRunLoopSourceRef  rls;
	CFSocketRef listeningSocket = CFSocketCreateWithNative(NULL, fdForListening, kCFSocketAcceptCallBack, callback, &context);
	if (listeningSocket == NULL) {
		return -1;
	} else {
		assert( CFSocketGetSocketFlags(listeningSocket) & kCFSocketCloseOnInvalidate );
		
		rls = CFSocketCreateRunLoopSource(NULL, listeningSocket, 0);
		assert(rls != NULL);
		
		CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
		CFRelease(rls);
		CFRelease(listeningSocket);
	} 
	
	socklen_t namelen = sizeof(serverAddress6);
	getsockname(fdForListening, (struct sockaddr *) &serverAddress6, &namelen);
	
	return ntohs(serverAddress6.sin6_port);
}

static NSMutableDictionary *myKeys = NULL;         // Advertise myself using these TXT records
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
#pragma unused(notification)
    
    NSSetUncaughtExceptionHandler(&catchallExceptionHandler);
		// Actually need to set this in the Info.plist file
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
	
	@autoreleasepool {
			// Do not show in dock. Works in OSX 10.7+
			// But stopped working in 10.8, sigh
			// ProcessSerialNumber psn = {0, kCurrentProcess};
			// TransformProcessType(&psn, kProcessTransformToUIElementApplication);
		
			// Create a uniqueID for ourselves if none existed
		if (myUniqueID == nil) {
			GetUniqueID *uid = [[GetUniqueID alloc] init];
			myUniqueID = [[NSString stringWithFormat:@"player-%@", [uid GetHWAddress]] retain];
		}
		
			// Register to listen for preferencepane notifications
		NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(prefcallbackWithNotification:) name:@"Preferences Changed" object:@"com.fxpal.displaycast.Player"];
		
#ifdef PLAYER_USE_XIB
			// Ugly initialization and making sure that all synthesized windows are minimized!!
		windows[0] = rw0;
		windows[1] = rw1;
		windows[2] = rw2;
		windows[3] = rw3;
		windows[4] = rw4;
		windows[5] = rw5;
		windows[6] = rw6;
		windows[7] = rw7;
		windows[8] = rw8;
		windows[9] = rw9;
		
		imageviewers[0] = riv0;
		imageviewers[1] = riv1;
		imageviewers[2] = riv2;
		imageviewers[3] = riv3;
		imageviewers[4] = riv4;
		imageviewers[5] = riv5;
		imageviewers[6] = riv6;
		imageviewers[7] = riv7;
		imageviewers[8] = riv8;
		imageviewers[9] = riv9;
		
			// Hide all of our windows
		for (int indx = 0; indx < NUM_SESSIONS; indx++) {
			NSWindow *win = windows[indx];
			
			activeNSSessions[indx] = nil;
			[win orderOut:self];
		}
#endif /* PLAYER_USE_XIB */
		
			// Start the Bonjour browser.
		self.browser = [[NSNetServiceBrowser alloc] init];
		[self.browser setDelegate:self];
		[self.browser searchForServicesOfType:STREAMER inDomain:BONJOUR_DOMAIN];

			// Register our service with Bonjour.
		in_port_t chosenPort = [self createServerSocketWithAcceptCallBack:ListeningSocketCallback];
		
		NSString *playerID = [[NSUserDefaults standardUserDefaults] stringForKey:myUniqueID];
		if (playerID == nil) {  // Generate a new player ID
			NSLog(@"Generating new unique ID for myself");
			
			CFUUIDRef uuidObj = CFUUIDCreate(nil);
			playerID = (NSString*)CFUUIDCreateString(kCFAllocatorDefault, uuidObj); // [(NSString*)CFUUIDCreateString(kCFAllocatorDefault, uuidObj) substringToIndex:8];
			[[NSUserDefaults standardUserDefaults] setObject:playerID forKey:myUniqueID];
			CFRelease(uuidObj);
			
			NSString *nm = NSFullUserName();
			NSString *str;
			if (nm == nil)
				str = @"Unknown's Player";
			else
				str = [NSString stringWithFormat:@"%@'s Player", nm];
			[[NSUserDefaults standardUserDefaults] setObject:str forKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
		}
		
			// Register ourselves in Bonjour
		netService = [[NSNetService alloc] initWithDomain:BONJOUR_DOMAIN type:PLAYER name:playerID port:chosenPort];
		if (netService != nil) {
				// Deprecated in 10.8
				// SInt32 major, minor, bugfix;
				// Gestalt(gestaltSystemVersion, &OSversion);
				// Gestalt(gestaltSystemVersionMajor, &major);
				// Gestalt(gestaltSystemVersionMinor, &minor);
				// Gestalt(gestaltSystemVersionBugFix, &bugfix);
				// NSString *systemVersion = [NSString stringWithFormat:@"OSX %d.%d.%d", major, minor, bugfix];
			NSString *systemVersion = [NSString stringWithFormat:@"OSX %@", [[NSProcessInfo processInfo] operatingSystemVersionString]];
			
				// The screen size of the primary display.
			CGRect screenBounds = CGDisplayBounds(CGMainDisplayID());
			
			NSString *ver = [[NSString alloc] initWithFormat:@"%f", VERSION];
			
			NSString *bluetoothID = @"NotSupported";
			/*
			 myKeys = [NSMutableDictionary dictionaryWithObjectsAndKeys:self.serviceName, @"name", [ NSString stringWithFormat:@"0x0x%.0fx%.0f", screenBounds.size.width, screenBounds.size.height], @"screen0", systemVersion, @"osVersion", @"NOTIMPL", @"locationID", [[NSHost currentHost] localizedName], @"machineName", nil];
			 */
			myKeys = [[NSMutableDictionary alloc] initWithObjectsAndKeys:self.serviceName, @"name", [ NSString stringWithFormat:@"0x0x%.0fx%.0f", screenBounds.size.width, screenBounds.size.height], @"screen0", systemVersion, @"osVersion", @"NOTIMPL", @"locationID", [[NSHost currentHost] localizedName], @"machineName", ver, @"version", NSUserName(), @"userid", bluetoothID, @"bluetooth", nil];
			[netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
			[netService setDelegate:self];
			[netService publishWithOptions:NSNetServiceNoAutoRename /* 0 */];
			
#ifdef USE_BLUETOOTH
				// This code used to work synchronously and then it was deprecated in 10.6 and now it just hangs when I compile in Lion+. Apple developer forum has no answer on why this fails!!
			[self performSelectorInBackground:@selector(getBluetoothDeviceAddress) withObject:nil];
#endif /* USE_BLUETOOTH */
		}
		
			// Create the taskbar UI
		NSString *path = [[NSBundle mainBundle] pathForResource:@"icon" ofType:@"tiff"];
		NSImage *image = [[NSImage alloc] initWithContentsOfFile: path ];
		
		trayItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
		[trayItem setMenu:statusMenu];
		[trayItem setHighlightMode:YES];
		[trayItem setImage: image];
    }
}

#ifdef USE_BLUETOOTH
- (void) getBluetoothDeviceAddress {
	NSString *bta = [[IOBluetoothHostController defaultController] addressAsString];

    [myKeys removeObjectForKey:@"bluetooth"];
    [myKeys setValue:bta forKey:@"bluetooth"];
    
    [netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
}
#endif /* USE_BLUETOOTH */
	
- (void)applicationWillTerminate:(NSNotification *)notification {
#pragma unused(notification)
}

#pragma mark -
#pragma mark * Bound properties
// The user interface uses Cocoa bindings to set itself up based on these
// KVC/KVO compatible properties.

- (NSMutableSet *)pendingServicesToAdd {
    if (self->_pendingServicesToAdd == nil) 
        self->_pendingServicesToAdd = [[NSMutableSet alloc] init];
    return self->_pendingServicesToAdd;
}

- (NSMutableSet *)pendingServicesToRemove {
    if (self->_pendingServicesToRemove == nil)
        self->_pendingServicesToRemove = [[NSMutableSet alloc] init];
    return self->_pendingServicesToRemove;
}

- (NSMutableSet *)services {
    if (self->_services == nil) {
        self->_services = [[NSMutableSet alloc] init];
    }
    return self->_services;
}

- (NSOperationQueue *)queue {
    if (self->_queue == nil) {
        self->_queue = [[NSOperationQueue alloc] init];
        assert(self->_queue != nil);
    }
    return self->_queue;
}

- (NSString *)serviceName
{
    if (self->_serviceName == nil) {
        self->_serviceName = [[self defaultServiceName] copy];
        assert(self->_serviceName != nil);
    }
    return self->_serviceName;
}

- (NSString *)defaultServiceName {
    GetUniqueID *uid = [[GetUniqueID alloc] init];
    if (myUniqueID == nil) 
        myUniqueID = [[NSString stringWithFormat:@"player-%@", [uid GetHWAddress]] retain];
    [uid release];
    
    assert(myUniqueID != nil);
    
    NSString *result = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
    if (result == nil) {
        NSString *str = NSFullUserName();
        
        if (str == nil)
            result = @"Unknown's Player";
        else
            result = [NSString stringWithFormat:@"%@'s Player", str];
        [[NSUserDefaults standardUserDefaults] setObject:result forKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
    }
    return result;
}

- (void)setServiceName:(NSString *)newValue {
    NSLog(@"setServiceName");
    
    assert(myUniqueID != nil);
    if (newValue != self->_serviceName) {
        [self->_serviceName release];
        self->_serviceName = [newValue copy];
        
        if (self->_serviceName == nil) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
        } else {
            [[NSUserDefaults standardUserDefaults] setObject:self->_serviceName forKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
        }
    }
}

#ifdef PLAYER_TASKBAR

#else /* PLAYER_TASKBAR */
- (NSArray *)sortDescriptors {
    if (self->_sortDescriptors == nil) {
        SEL selector;
        
        if ([[NSString string] respondsToSelector:@selector(localizedStandardCompare)])
            selector = @selector(localizedStandardCompare:);
        else
            selector = @selector(localizedCaseInsensitiveCompare:);
        
        self->_sortDescriptors = [[NSArray alloc] 
                                  initWithObjects:[[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:selector] autorelease], nil];
    }
    return self->_sortDescriptors;
}

+ (NSSet *)keyPathsForValuesAffectingIsReceiving {
    return [NSSet setWithObject:@"runningOperations"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &self->_queue) {
        assert([keyPath isEqual:@"isFinished"]);
        
        // IMPORTANT
        // ---------
        // KVO notifications arrive on the thread that sets the property.  In this case that's 
        // always going to be the main thread (because FileReceiveOperation is a concurrent operation 
        // that runs off the main thread run loop), but I take no chances and force us to the 
        // main thread.  There's no worries about race conditions here (one of the things that 
        // QWatchedOperationQueue solves nicely) because AppDelegate lives for the lifetime of 
        // the application.
        
        [self performSelectorOnMainThread:@selector(didFinishOperation:) withObject:object waitUntilDone:NO];
    }
    if (NO) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}
#endif /* PLAYER_TASKBAR */

#pragma mark * Actions
#ifdef PLAYER_TASKBAR
- (IBAction)streamAction:(id)sender {
    assert([sender isKindOfClass:[NSMenuItem class]]);
    NSMenuItem *clickedEntry = sender;
    MenuEntry *entry = nil;
    
	for (entry in streamer) {
        if ([[entry menuItem] isEqual:clickedEntry])
            break;
    }
    
    assert(entry != nil);
    
    // First check whether this is a duplicate
    for (int indx = 0; indx < NUM_SESSIONS; indx++) {
        if (activeNSSessions[indx] == nil)
            continue;
        
        if ([[activeNSSessions[indx] name] isEqualToString:[[entry ns] name]]) {
            [clickedEntry setState:NSOffState];
            stopSession[indx] = true;
            // [windows[indx] orderFrontRegardless];
            
            return;
        }
    }
    
    // Next see if there is space
    for (int indx = 0; indx < NUM_SESSIONS; indx++) {
        if (activeNSSessions[indx] == nil) {
            activeNSSessions[indx] = [entry ns];
            [NSThread detachNewThreadSelector:@selector(receiveFromService:) toTarget:self withObject:[entry ns]];
            
            [clickedEntry setState:NSOnState];
            return;
        }
    }
    
    NSLog(@"FATAL: Too many sessions");
    
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setAlertStyle:NSInformationalAlertStyle];
    [alert setMessageText:@"Limit Failure"];
    [alert setInformativeText:@"Currently, we only display 10 sessions"]; 
}

#ifdef PLAYER_USE_STREAMERICON
- (void)updateMenuItemIcon:(NSTimer *)t {
    MenuEntry *me = [t userInfo];
    
	if ([me menuItem] == nil) {	// The streamer left - clean
		[t invalidate];
		
		return;
	}
	
    NSDictionary *myCurKeys = [NSNetService dictionaryFromTXTRecordData:[[me ns] TXTRecordData]];
    int imagePort = [[[[NSString alloc] initWithData:[myCurKeys objectForKey:@"imagePort" ] encoding:NSASCIIStringEncoding] autorelease] intValue];
    if (imagePort > 0) {
        NSArray *addresses = [[me ns] addresses];
        NSData *address;
        struct sockaddr_in address_sin;
        int receiveSocket;
		BOOL accessible = FALSE;

        for (address in addresses) {
            memcpy(&address_sin, (struct sockaddr_in *)[address bytes], sizeof(struct sockaddr_in));
            address_sin.sin_port = (short) htons(imagePort);
            
			char buffer[1024];
				// NSLog(@"DEBUG: Trying image port ... %s:%d", inet_ntop(AF_INET, &(address_sin.sin_addr), buffer, sizeof(buffer)), ntohs(address_sin.sin_port));
            
            if (address_sin.sin_family == AF_INET) {
				fd_set fdset;
				struct timeval tv;

                receiveSocket = socket(AF_INET, SOCK_STREAM, 0);
				fcntl(receiveSocket, F_SETFL, O_NONBLOCK);
				connect(receiveSocket, (struct sockaddr *)&address_sin, (socklen_t)sizeof(struct sockaddr_in));
				
				FD_ZERO(&fdset);
				FD_SET(receiveSocket, &fdset);
				tv.tv_sec = 1;             /* 1 second timeout */
				tv.tv_usec = 0;
				
				if (select(receiveSocket + 1, NULL, &fdset, NULL, &tv) == 1) {
					int so_error;
					socklen_t len = sizeof so_error;
					
					getsockopt(receiveSocket, SOL_SOCKET, SO_ERROR, &so_error, &len);
					close(receiveSocket);
					
					if (so_error == 0) {
						close(receiveSocket);
						
						NSString *imageURL = [NSString stringWithFormat:@"http://%s:%d/snapshot?width=%d", inet_ntop(AF_INET, &(address_sin.sin_addr), buffer, sizeof(buffer)), imagePort, (PLAYER_ICON_SIZE)];

							// NSLog(@"Downloading image from %@", imageURL);
						accessible = TRUE;
						
						dispatch_queue_t queue = dispatch_queue_create("com.fxpal.displaycast.player.asyncImageDownload", NULL);
						NSMenuItem *mi = [me menuItem];
						
						dispatch_async(queue, ^{
							NSURL *url = [[NSURL alloc] initWithString:imageURL];
							NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
							if (image != NULL) {
								if ([mi respondsToSelector:@selector(setImage:)])
									[mi setImage:image];
								[image release];
							}
							[url release];
						});
						dispatch_release(queue);
						
						break;
					}
				}
            }
        }
		if (accessible == FALSE)
			[t invalidate];
    } else {
		[t invalidate];
	}
}
#endif /* PLAYER_USE_STREAMERICON */

- (void) addEntry:(NSNetService *)ns {
    if (streamer == nil)
        streamer = [[NSMutableArray alloc] init];
    else {
        unsigned long count = [streamer count];
        for (unsigned int i=0; i < count; i++) {
            MenuEntry *object = [streamer objectAtIndex:i];
            
            if ([[ns name] isEqualToString:[object name]]) {
                [object updateNS:ns];
                
                return;
            }
        }
    }
    
    NSDictionary *myCurKeys = [NSNetService dictionaryFromTXTRecordData:[ns TXTRecordData]];
    NSData *data = [myCurKeys objectForKey:@"name"];
    NSString *fullName = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:fullName action:@selector(streamAction:) keyEquivalent:@""] autorelease];
    MenuEntry *me = [[[MenuEntry alloc] initWithNS:ns andMenuItem:item] autorelease];
    [item setTarget:self];

#ifdef PLAYER_USE_STREAMERICON
    NSTimer *t = [NSTimer timerWithTimeInterval:300.0 target:self selector:@selector(updateMenuItemIcon:) userInfo:me repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSEventTrackingRunLoopMode];

    [t fire];
#endif /* PLAYER_USE_STREAMERICON */
    
    [streamMenu addItem:item];
    [streamer addObject:me];
}

- (void) delEntry:(NSNetService *)ns {
	MenuEntry *toDelete;
	
	for (toDelete in streamer) {
			// unsigned long count = [streamer count];
			// for (unsigned int i=0; i < count; i++) {
			// MenuEntry *object = [streamer objectAtIndex:i];
        
        if ([[ns name] isEqualToString:[toDelete name]]) 
			break;
    }
	if (toDelete != nil) {
		[toDelete removeEntry:streamMenu];
		[streamer removeObject:toDelete];
	} else
		NSLog(@"DEBUG: Trying to delete non-existent entry: %@", ns);
}

- (IBAction)tableRowClickedAction:(id)sender {
#pragma unused(sender)
}

#else
- (IBAction)tableRowClickedAction:(id)sender {
#pragma unused(sender)
    
    // We test for a positive clickedRow to eliminate clicks in the column headers.
    if ( ([sender clickedRow] >= 0) && [[self.servicesArray selectedObjects] count] != 0) {
        PlayerListing *pl = [[self.servicesArray selectedObjects] objectAtIndex:0];
        assert([pl isKindOfClass:[PlayerListing class]]);
        
        NSNetService *service = [pl ns];
        assert([service isKindOfClass:[NSNetService class]]);
        
        // First check whether this is a duplicate
        NSString *servName = [service name];
        for (int indx = 0; indx < NUM_SESSIONS; indx++) {
            NSNetService *ns = activeNSSessions[indx];
            
            if (ns == nil)
                continue;
            
            if ([[ns name] isEqualToString:servName]) {
                [windows[indx] orderFrontRegardless];
                
                return;
            }
        }
        
        // Next see if there is space
        for (int indx = 0; indx < NUM_SESSIONS; indx++) {
            if (activeNSSessions[indx] == nil) {
                activeNSSessions[indx] = service;
                [NSThread detachNewThreadSelector:@selector(receiveFromService:) toTarget:self withObject:service];
                
                return;
            }
        }
        
        NSLog(@"FATAL: Too many sessions");
        
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setAlertStyle:NSInformationalAlertStyle];
        [alert setMessageText:@"Limit Failure"];
        [alert setInformativeText:@"Currently, we only display 10 sessions"]; 
    }
}
#endif /* PLAYER_TASKBAR */

- (void)stopBrowsingWithStatus:(NSString *)status {
#pragma unused(status)
    assert(status != nil);
    
    [self.browser setDelegate:nil];
    [self.browser stop];
    self.browser = nil;
    
#ifndef PLAYER_TASKBAR
    [self.pendingServicesToAdd removeAllObjects];
    [self.pendingServicesToRemove removeAllObjects];
    
    [self willChangeValueForKey:@"services"];
    [self.services removeAllObjects];
    [self  didChangeValueForKey:@"services"];
#endif /* PLAYER_TASKBAR */
}

#pragma mark -
#pragma mark Graphics Stuff
void drawWin(UInt32 *windowData, int width, int height, int x, int y, int w, int h, UInt32 *buf) {
#pragma unused(height)
    
    if (buf != NULL)
        for (int iy = 0; iy < h; iy++) {
            for (int ix = 0; ix < w; ix++) {
                if (*buf != 0x00FFFFFF) {
                    int indx = ((int) width * (y + iy)) + (x + ix);
                    
                    *(windowData + indx) = *buf;
                }
                buf++;
            }
        }
}

void releaseProvider(void *info, const void *data, size_t size) {
#pragma unused(info)
	NSLog(@"Should I free something here of size %zd", size);
	free((void *)data);
}

void displayWin(NSImageView *player, int width, int height, int maskX, int maskY, int maskWidth, int maskHeight, UInt32 *buf) {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef bitmapData = CGDataProviderCreateWithData(NULL, buf, width * height * sizeof(UInt32), NULL /* releaseProvider */);
    CGImageRef myImage = CGImageCreate(width, 
                                       height,
                                       sizeof(UInt8) * 8,
                                       sizeof(UInt32) * 8,
                                       width * sizeof(UInt32),
                                       colorSpace,
                                       (/* kCGImageAlphaNoneSkipFirst */ kCGImageAlphaPremultipliedFirst |kCGBitmapByteOrder32Host),
                                       bitmapData,
                                       NULL,
                                       false,
                                       kCGRenderingIntentDefault);
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:myImage];
    NSImage *image = [[NSImage alloc] init];
    
    [image addRepresentation:bitmapRep];
	[image setCacheMode:NSImageCacheNever];
    /*
     NSRect srcRect, destRect;
     srcRect = NSMakeRect((CGFloat) maskX, (CGFloat) maskY, (CGFloat) maskWidth, (CGFloat) maskHeight);
     destRect = NSMakeRect(0.0, 0.0, (CGFloat) width, (CGFloat) height);
     [image drawInRect:destRect fromRect:srcRect operation:NSCompositeSourceOver fraction:1.0];
     */

		// [[player image] release];
    if ((maskX == 0) && (maskY == 0) && (maskWidth == width) && (maskHeight == height)) 
        [player setImage:image];
    else 
        [player setImage:image];

#if 0
    {
        NSImage *result = [[[NSImage alloc] initWithSize:NSMakeSize(maskWidth, maskHeight)] autorelease];
        
        [result lockFocus];
        // [[NSGraphicsContext currentContext] setShouldAntialias:NO];
        // [image  compositeToPoint:NSZeroPoint fromRect:NSMakeRect(maskX, maskY, maskWidth, maskHeight) operation:NSCompositeCopy fraction:1.0];
        [image drawInRect:NSMakeRect(0.0, 0.0, width, height) fromRect:NSMakeRect(maskX, maskY, maskWidth, maskHeight) operation:NSCompositeCopy fraction:1.0];
        [result unlockFocus];
        
        [player setImage:result];
        [image release];
    }
#endif /* 0 */

  	[image release];
    [bitmapRep release];
    
    CGImageRelease(myImage);
    CGDataProviderRelease(bitmapData);
    CGColorSpaceRelease(colorSpace);
}

#pragma mark Runs as a thread, processing data from a particular streamer
- (void)updateKey:(NSWindow *)window andNSNetService: (NSNetService *)ns{
    NSRect geom = [[window contentView] frame];
    // NSRect geom = [window frame];
    
    // NSLog(@"Window state changed");
    NSString *playerID = [[NSUserDefaults standardUserDefaults] stringForKey:myUniqueID];
    NSString *session = [[[NSString alloc] initWithFormat:@"%@ %@ %.0f %.0f %.0f %.0f %d %d", [ns name], playerID, geom.origin.x, geom.origin.y, geom.size.width, geom.size.height, ([window isMiniaturized] ? 1:0), ([window isZoomed] ? 1:0)] autorelease];
    
    NSString *myObjID = [[[NSString alloc] initWithFormat:@"%lu", [window hash]] autorelease];
    [myKeys removeObjectForKey:myObjID];
    [myKeys setValue:session forKey:myObjID];
    
    [netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
}

#pragma mark -
#pragma mark * The main displaycast functionality. Watch the streamer
- (void)receiveFromService:(NSNetService *)ns {
    assert(ns != nil);
	
    @autoreleasepool {
		UInt8 *receiveBuf = NULL;        // Buffer for receiving network datagrams
		UInt32 *winData = NULL;          // Backing store for the window. 
		int pWidth = -1, pHeight = -1;   // Previous width and height to detect and perhaps 
		unsigned int pmaskX = -1, pmaskY = -1, pmaskWidth = -1, pmaskHeight = -1;
		UInt8 *updateData = NULL, *tmpUpdateData = NULL;       // Buffer for receiving updates
		
			// Figure out what window I am supposed to operate on
		int sessionIndex;
		for (sessionIndex = 0; sessionIndex < NUM_SESSIONS; sessionIndex++ ) {
			if (activeNSSessions[sessionIndex] == ns)
				break;
		}
		if (sessionIndex == NUM_SESSIONS) {
			NSLog(@"FATAL: Something is wrong");
			
			return;
		}
		stopSession[sessionIndex] = false;
		int receiveSocket = socket(AF_INET, SOCK_STREAM, 0);
		
			// Try to find the Streamer's network address that is accessible by me
		boolean_t connected = false;
		for (NSData *address in [ns addresses]) {
			struct sockaddr_in *address_sin = (struct sockaddr_in *)[address bytes];
			
			char buffer[1024];
			NSLog(@"DEBUG: Trying... %s:%d", inet_ntop(AF_INET, &(address_sin->sin_addr), buffer, sizeof(buffer)), ntohs(address_sin->sin_port));
			
			if (address_sin->sin_family == AF_INET) {
				if (connect(receiveSocket, (struct sockaddr *)address_sin, (socklen_t)sizeof(struct sockaddr_in)) == 0) {
					struct timeval tv;
					
					tv.tv_sec  = 60*60;		// Wait for a hour to give up
					tv.tv_usec = 0;
					setsockopt(receiveSocket, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
					
					connected = true;
					break;
				}
			}
		}
		
		if (connected) {
			NSWindow *window = nil;
			NSImageView *player = nil;
			
			while (stopSession[sessionIndex] != true) {
				ssize_t len;
				UInt32 pktSize;
				
					// First receive the packet size
				if (recv(receiveSocket, &pktSize, sizeof(pktSize), 0) <= 0) 
					break;
				
					// Now receive this much data - freeing memory from prior loops
				if (receiveBuf)
					free(receiveBuf);
				receiveBuf = malloc(pktSize);
				
				len = 0;
				while ((UInt32) len < pktSize) {
					ssize_t recvLen = recv(receiveSocket, receiveBuf + len, pktSize - len, 0);
					if (recvLen <= 0) 
						break;
					len += recvLen;
				}
				if (len != pktSize)
					break;
				
				z_stream strm;
				UInt32 out[5];  // space for the first five integers
				unsigned int width, height, x, y, w, h;
				unsigned int maskX, maskY, maskWidth, maskHeight;
				
					// First, uncompress the first five integers which repreent the width, height, maskX, maskY, maskW, maskH, x, y, w and h
				/* allocate inflate state */
				strm.zalloc = Z_NULL;
				strm.zfree = Z_NULL;
				strm.opaque = Z_NULL;
				strm.avail_in = 0;
				strm.next_in = Z_NULL;
				if (inflateInit(&strm) != Z_OK)
					exit(1);
				
				strm.avail_in = (uInt) pktSize;
				strm.next_in = receiveBuf;
				int flush = Z_NO_FLUSH; // Z_BLOCK;
				
				strm.avail_out = sizeof(out);
				strm.next_out = (unsigned char *)out;
				switch (inflate(&strm, flush)) {
					case Z_STREAM_ERROR:
						NSLog(@"HEADER Z_STREAM_ERROR %d", strm.avail_out);
						(void)inflateEnd(&strm);
						continue;
						
					case Z_NEED_DICT:
						NSLog(@"HEADER Z_NEED_DICT");
						(void)inflateEnd(&strm);
						continue;
						
					case Z_DATA_ERROR:
						NSLog(@"HEADER Z_DATA_ERROR %d", pktSize);
						(void)inflateEnd(&strm);
						continue;
						
					case Z_MEM_ERROR:
						NSLog(@"HEADER Z_MEM_ERROR");
						(void)inflateEnd(&strm);
						continue;
				}
				
				width = ntohl(out[0])>>16;
				height = ntohl(out[0])&0xffff;
				maskX = ntohl(out[1])>>16;
				maskY = ntohl(out[1])&0xffff;
				maskWidth = ntohl(out[2])>>16;
				maskHeight = ntohl(out[2])&0xffff;
				x = ntohl(out[3])>>16;
				y = ntohl(out[3])&0xffff;
				w = ntohl(out[4])>>16;
				h = ntohl(out[4])&0xffff;
				
				assert(w<=width);
				assert(h<=height);
				
					// If this is the first time, then create a new window to show 
				if (((int) width !=  pWidth) || ((int) height != pHeight)) {
					if (pWidth != -1) {
						NSLog(@"Dynamically changing window size not support yet %dx%d from %dx%d", width, height, pWidth, pHeight);
						break;
					} else
						NSLog(@"Setting window of size %dx%d", width, height);
					pWidth = width;
					pHeight = height;
						// winData = calloc(width * height, sizeof(UInt32));
					updateData = malloc(width * height * sizeof(UInt32));   // Allocate once and reuse
					tmpUpdateData = malloc(width * height * sizeof(UInt32));    // Needed for bitmap encoding
					assert(updateData != NULL);
					assert(tmpUpdateData != NULL);
					
#ifdef PLAYER_USE_XIB
					window = windows[sessionIndex]; // [windows objectAtIndex:indx];
					[window setContentSize:NSMakeSize(width, height)];
					player = imageviewers[sessionIndex]; // [imageviewers objectAtIndex:indx];
					[player setFrame:NSMakeRect(0.0, 0.0, width, height)];
					[window setDelegate:self];
					
#if 0
					NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:[[window contentView] frame]];
					[scrollView setHasVerticalScroller:YES];
					[scrollView setHasHorizontalScroller:YES];
					[scrollView setBorderType:NSNoBorder];
					[scrollView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
					[scrollView setMaxMagnification:4.0];
					[scrollView setMinMagnification:0.25];
					
					[scrollView setDocumentView:player];
					[window setContentView:scrollView];
					[scrollView release];
#endif /* 0 */
#else	/* PLAYER_USE_XIB */
					window = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, 0, width, height) 
														 styleMask:(NSResizableWindowMask | NSTexturedBackgroundWindowMask | NSTitledWindowMask | NSClosableWindowMask |NSMiniaturizableWindowMask)
														   backing:NSBackingStoreBuffered 
															 defer:NO];
					[window setDelegate:self];
					[window setHasShadow:YES];
					
					player = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (float) width, (float) height)];
						// [player setInterfaceStyle:NSWindows95InterfaceStyle];
					[player setEditable:NO];
					
					[[window contentView] addSubview: player];
						// [[rw1 contentView] addSubview: rootImageViewer];
					
						// [window makeKeyAndOrderFront: self];
						// [window makeMainWindow];
					
#endif /* PLAYER_USE_XIB */
					
						// Now, set the window title to the Streamer name
					NSDictionary *keys = [NSNetService dictionaryFromTXTRecordData:[ns TXTRecordData]];
					NSData *data = [keys objectForKey:@"name"];
					NSString *name = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
						// [[window title] release];
					[window setTitle:name];
					
						// [window setExcludedFromWindowsMenu:NO];
					[window setContentAspectRatio:NSMakeSize((float) width, (float)height)];
					[window orderFront:self];
					[window setIsZoomed:YES];
					
					[netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
					
					[self updateKey:window andNSNetService:ns];
					
#ifdef PLAYER_LION_FS
					if (OSversion >= 0x1070)
						if (([window styleMask] & NSFullScreenWindowMask) != NSFullScreenWindowMask)
							[window toggleFullScreen:nil];
#endif /* PLAYER_LION_FS */
				}
				
				if (! ((pmaskX == maskX) && (pmaskY == maskY) && (pmaskWidth == maskWidth) && (pmaskHeight == maskHeight)) ) {
					if (winData == NULL)
						winData = malloc(width * height * sizeof(UInt32));
					else
						bzero(winData, width * height * sizeof(UInt32));
					assert(winData != NULL);
					
					displayWin(player, width, height, maskX, maskY, maskWidth, maskHeight, winData);
					
					pmaskX = maskX;
					pmaskY = maskY;
					pmaskWidth = maskWidth;
					pmaskHeight = maskHeight;
				}
				
				/* run inflate() on input until output buffer not full */
					// UInt8 *updateData = malloc(w * h * sizeof(UInt32));
				unsigned long uncompressed = 0;
					// UInt8 *updPtr = updateData;
				int sz;
				do {
					sz = (int) ((w * h * sizeof(UInt32)) - uncompressed);
					strm.avail_out = sz;
					strm.next_out = tmpUpdateData + uncompressed;
					
					int ret_value = inflate(&strm, flush);
					switch (ret_value) {
						case Z_STREAM_ERROR:
							if (sz != (int) strm.avail_out)
								NSLog(@"DATA Z_STREAM_ERROR %d", (int) ((w * h * sizeof(UInt32)) - uncompressed));
							break;
							
						case Z_NEED_DICT:
							NSLog(@"DATA Z_NEED_DICT");
							break;
							
						case Z_DATA_ERROR:
							if (sz != (int) strm.avail_out)
								NSLog(@"DATA Z_DATA_ERROR %d", (int) ((w * h * sizeof(UInt32)) - uncompressed));
							break;
							
						case Z_MEM_ERROR:
							NSLog(@"DATA Z_MEM_ERROR");
							break;
					}
					uncompressed += strm.avail_out;
						// } while (uncompressed < (w * h * sizeof(UInt32)));
				} while (sz != (int) strm.avail_out);
				
				/* clean up and return */
				(void)inflateEnd(&strm);
				
					// Now perform bitmap encoding's decoding
				int bmStart = 0;
				int srcStart = w*h;
				
				if (tmpUpdateData != NULL) {        // Shouldn't need this test - Xcode complains!!
					for (unsigned int j = 0; j < h; j++) {
						for (unsigned int i = 0; i < w; i++) {
							if (tmpUpdateData[bmStart] == 0xFF) {
								updateData[bmStart * sizeof(UInt32)] = tmpUpdateData[srcStart++];
								updateData[bmStart * sizeof(UInt32) + 1] = tmpUpdateData[srcStart++];
								updateData[bmStart * sizeof(UInt32) + 2] = tmpUpdateData[srcStart++];
								updateData[bmStart * sizeof(UInt32) + 3] = 0xFF;
							} else {
								updateData[bmStart * sizeof(UInt32)] = 0xFF;
								updateData[bmStart * sizeof(UInt32) + 1] = 0xFF;
								updateData[bmStart * sizeof(UInt32) + 2] = 0xFF;
								updateData[bmStart * sizeof(UInt32) + 3] = 0x00;
							}
							bmStart++;
						}
					}
				}
				
				if (winData == NULL) {
					assert((w == width) && (h == height));
					
					winData = malloc(width * height * sizeof(UInt32));
					assert(winData != NULL);
					memcpy(winData, updateData, width * height * sizeof(UInt32));
				} else {
						// Overlay the update onto my view of the frame
					drawWin(winData, width, height, x, y, w, h, (UInt32 *) updateData);
				}
				
					// Now, display my view of the frame
				displayWin(player, width, height, maskX, maskY, maskWidth, maskHeight, winData);
			}
		} 
		
		NSWindow *win = windows[sessionIndex];
		[win orderOut:self];
		
#ifdef PLAYER_TASKBAR
		MenuEntry *entry = nil;
		
		unsigned long count = [streamer count];
		for (unsigned int i=0; i < count; i++) {
			entry = [streamer objectAtIndex:i];
			
			if ([[[entry ns] name] isEqual:[ns name]]) {
				[[entry menuItem] setState:NSOffState];
				break;
			}
		}
#endif /* PLAYER_TASKBAR */	
		[ns stop];
		activeNSSessions[sessionIndex] = nil;
		
		close(receiveSocket);
		if (receiveBuf)
			free(receiveBuf);
		if (winData)
			free(winData);
		if (updateData)
			free(updateData);
		if (tmpUpdateData)
			free(tmpUpdateData);
	}
}
@end

@implementation PlayerAppDelegate (NSWindowDelegate)
#pragma mark -
#pragma mark * Window event handlers
- (void)windowStateChanged:(NSNotification *)notification {
    NSWindow *window = [notification object];
    
    for (int sessionIndex = 0; sessionIndex < NUM_SESSIONS; sessionIndex++ ) {
        if (windows[sessionIndex] == window) {
            [self updateKey:window andNSNetService:activeNSSessions[sessionIndex]];
            break;
        }
    }
}

- (void)windowDidResize:(NSNotification *)notification {
    [self windowStateChanged:notification];
}

- (void)windowDidMove:(NSNotification *)notification {
    [self windowStateChanged:notification];
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
    [self windowStateChanged:notification];
}
- (void)windowDidDeminiaturize:(NSNotification *)notification {
    [self windowStateChanged:notification];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    [self windowStateChanged:notification];
}
- (void)windowDidExitFullScreen:(NSNotification *)notification {
    [self windowStateChanged:notification];
}

- (void)windowWillClose:(NSNotification *)notification {
    NSWindow *window = [notification object];
    
    for (int sessionIndex = 0; sessionIndex < NUM_SESSIONS; sessionIndex++ ) {
        if (windows[sessionIndex] == window) {
            stopSession[sessionIndex] = true;
            [window orderOut:self];
			
			if (activeNSSessions[sessionIndex] != nil) {
				activeNSSessions[sessionIndex] = nil;
				
				NSString *myID = [[[NSString alloc] initWithFormat:@"%lu", [window hash]] autorelease];
				[myKeys removeObjectForKey:myID];
				[netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
			}
            break;
        }
    }
    
}
@end

@implementation PlayerAppDelegate (NSNetServiceDelegate)
#pragma mark -
#pragma mark * Bonjour stuff
- (void)netServiceDidPublish:(NSNetService *)sender {
#pragma unused(sender)
    // assert(sender == self.netService);
    // Bonjour might have changed our name, we are not going to save this temporary name [sender name]
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict {
#pragma unused(sender, errorDict)
    // assert(sender == self.netService);
    // NSLog(@"DEBUG: Did not publish - %@, %@", [sender name], errorDict);
    NSLog(@"FATAL: Failed to publish ourselves. Duplicate?");

		// Turns out that 
		// exit(0);
}
@end

@implementation PlayerAppDelegate (NSNetServiceBrowserDelegate)
#pragma mark -
#pragma mark * Bonjour Browsing
- (void)netService:(NSNetService *)ns didUpdateTXTRecordData:(NSData *)data {
#ifdef PLAYER_TASKBAR
#pragma unused(data)
    [self addEntry:ns];
#else
    NSString *nm = [ns name];
    
    // Pick the player listing to update the name
    for (PlayerListing *pl in self.servicesArray.content) {
        NSNetService *plns = [pl ns];
        if ([[plns name] isEqualToString:nm]) {
            NSDictionary *keys = [NSNetService dictionaryFromTXTRecordData:data];
            NSData *dt = [keys objectForKey:@"name"];
            NSString *name = [[[NSString alloc] initWithData:dt encoding:NSUTF8StringEncoding] autorelease];
            
            // [[pl name] release];
            [pl setName:name];
            
            NSLog(@"Updated txt record name to %@", name);
            
            // [dt release];
            // [keys release];
        }
    }
#endif /* PLAYER_TASKBAR */
}

- (void)netServiceDidResolveAddress:(NSNetService *)ns {
#ifndef PLAYER_TASKBAR
    NSString *nm = [ns name];
    
    for (PlayerListing *pl in self.servicesArray.content) {
        NSNetService *plns = [pl ns];
        if ([[plns name] isEqualToString:nm]) {
            NSLog(@"Duplicate resolution?");
            [ns stop];
            
            return;
        }
    }
    
    // PlayerListing *pl = [[PlayerListing alloc] initWithName:[ns name] andService:ns];
    PlayerListing *pl = [[PlayerListing alloc] init];
    [pl setNs:ns];
    
    // This name will later be overridden when we get the TXT record update
    [pl setName:@"Resolving name..."];
    
    // NSLog(@"I am setting PlayerListing to %@", [ns name]);
    NSSet *setToAdd = [[NSSet alloc] initWithObjects:pl, nil];
    
    [self willChangeValueForKey:@"services" withSetMutation:NSKeyValueUnionSetMutation usingObjects:setToAdd];
    [self.services addObject:pl];
    [self  didChangeValueForKey:@"services" withSetMutation:NSKeyValueUnionSetMutation usingObjects:setToAdd];
    
    [setToAdd release];
#endif /* PLAYER_TASKBAR */
    
    [ns startMonitoring];   // For txt record updates
}

- (void)netService:(NSNetService *)ns didNotResolve:(NSDictionary *)errorDict {
	switch ((NSInteger)[errorDict objectForKey:NSNetServicesErrorCode]) {
		case NSNetServicesTimeoutError: {
			NSLog(@"Timeout resolving %@", [ns name]);
			break;
		}
		default: {
			NSLog(@"Did not resolve %@ because of %@", [ns name], errorDict);
			break;
		}
	}
    
    [ns stop];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
#pragma unused(moreComing)
    
    assert(aNetServiceBrowser == self.browser);
#pragma unused(aNetServiceBrowser)
    
    [aNetService retain];
    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:5.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
#pragma unused(aNetServiceBrowser)
#ifdef PLAYER_TASKBAR
#pragma unused(moreComing)
    NSNetService *ns = aNetService;
    
    [self delEntry:aNetService];
#else
    assert(aNetServiceBrowser == self.browser);
    
    NSString *nm = [aNetService name];
    assert(nm != nil);
    
    NSNetService *ns = nil;
    // NSString *nsm;
    
    // PlayerListing *pl = nil;
    for (PlayerListing *p in self.servicesArray.content) {
        ns = [p ns];
        // nsm = [[NSString alloc] initWithString:[ns name]];
        // NSLog(@"WTF: %@ vs %@", nsm, nm);
        if ([[ns name] isEqualToString:nm]) {
            [self.pendingServicesToRemove addObject:p];
            // pl = p;
            
            break;
        }
    }
    assert(ns != nil);
#endif /* PLAYER_TASKBAR */
    
    // If this session was active, remove and close the window
    for (int indx = 0; indx < NUM_SESSIONS; indx++ ) {
        // NSLog("WTF: %@", activeNSSessions[indx]);
        if (activeNSSessions[indx] == ns) {
            [windows[indx] orderOut:self];
            [activeNSSessions[indx] stop];
            
            activeNSSessions[indx] = nil;
        }
    }
    [aNetService stop];
    
#ifndef PLAYER_TASKBAR
    if ( ! moreComing ) {
        NSSet *setToRemove;
        
        setToRemove = [self.pendingServicesToRemove copy];
        assert(setToRemove != nil);
        [self.pendingServicesToRemove removeAllObjects];
        
        [self willChangeValueForKey:@"services" withSetMutation:NSKeyValueMinusSetMutation usingObjects:setToRemove];
        [self.services minusSet:setToRemove];
        [self  didChangeValueForKey:@"services" withSetMutation:NSKeyValueMinusSetMutation usingObjects:setToRemove];
        
        [setToRemove release];
    }
#endif /* PLAYER_TASKBAR */
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser {
    assert(aNetServiceBrowser == self.browser);
#pragma unused(aNetServiceBrowser)
    [self stopBrowsingWithStatus:@"Service browsing stopped."];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict {
    assert(aNetServiceBrowser == self.browser);
#pragma unused(aNetServiceBrowser)
    assert(errorDict != nil);
#pragma unused(errorDict)
    [self stopBrowsingWithStatus:@"Service browsing failed."];
}
@end
