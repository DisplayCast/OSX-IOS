// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "Preferences.h"
#import "GetUniqueID.h"

@implementation Preferences
static CFStringRef streamerAppID = nil;
static CFStringRef playerAppID = nil;
static CFStringRef archiverAppID = nil;

- (void)assignMainView {
    [super assignMainView];
	
		// set the proper key view ordering
	[self setInitialKeyView:streamerName];
	[self setFirstKeyView:streamerName];
}

-(id)initWithBundle:(NSBundle*)bundle {
#pragma unused(bundle)
		// const char* const appID = [[[NSBundle bundleForClass:[self class]] bundleIdentifier] cStringUsingEncoding:NSASCIIStringEncoding]; // Get the bundle identifier -> com.yourcompany.whatever
		// CFStringRef bundleID = CFStringCreateWithCString(kCFAllocatorDefault, appID, kCFStringEncodingASCII);
	if ((self = [super initWithBundle:bundle]) != nil) {
		streamerAppID = CFSTR("com.fxpal.displaycast.Streamer");
		playerAppID = CFSTR("com.fxpal.displaycast.Player");
		archiverAppID = CFSTR("com.fxpal.displaycast.Archiver");
	}

	return self;
}

- (void)mainViewDidLoad {
	if (myUniqueID == nil) {
		GetUniqueID *uid = [[GetUniqueID alloc] init];
		myUniqueID = [uid GetHWAddress];
		[uid release];
	}
	assert(myUniqueID != nil);
	
	CFUUIDRef	uuidObj = CFUUIDCreate(nil);
	
	NSString *name = [NSString stringWithFormat:@"streamer-%@-Name", myUniqueID];
	CFStringRef streamID, stmp = (CFStringRef)CFPreferencesCopyAppValue((CFStringRef) name, streamerAppID);
		//	NSLog(@"WTF: %@ %@", name, stmp);
	
	if (stmp == nil) {
		NSString *str = NSFullUserName();
		if (str == nil)
			streamID = (CFStringRef) @"Unknown's Streamer";
		else
			streamID = (CFStringRef) [NSString stringWithFormat:@"%@'s Streamer", str];
		
		CFPreferencesSetAppValue((CFStringRef)name, streamID, streamerAppID);
		stmp = CFUUIDCreateString(nil, uuidObj);
		NSString *uidStr = (NSString *)stmp; // [(NSString*)stmp substringToIndex:8];
		CFPreferencesSetAppValue((CFStringRef)[NSString stringWithFormat:@"streamer-%@", myUniqueID], uidStr , streamerAppID);
		CFPreferencesAppSynchronize(streamerAppID);		
	} else
		streamID = (CFStringRef)[NSString stringWithString:(NSString *)stmp];
	CFRelease(stmp);
		// CFRelease(name);
	[streamerName setStringValue:(NSString *)streamID];
		// CFRelease(streamID);
	
	name = [NSString stringWithFormat:@"player-%@-Name", myUniqueID];
	CFStringRef playerID;
	stmp = (CFStringRef)CFPreferencesCopyAppValue((CFStringRef)name, playerAppID);
	if (stmp == nil) {
		NSString *str = NSFullUserName();
		if (str == nil)
			playerID = (CFStringRef) @" Player";
		else
			playerID = (CFStringRef) [NSString stringWithFormat:@"%@'s Player", str];
		
		CFPreferencesSetAppValue((CFStringRef)name, playerID, playerAppID);
		stmp = CFUUIDCreateString(nil, uuidObj);
		NSString *uidStr = (NSString *)stmp; // [(NSString*)stmp substringToIndex:8];
		CFPreferencesSetAppValue((CFStringRef)[NSString stringWithFormat:@"player-%@", myUniqueID], uidStr, playerAppID);
		CFPreferencesAppSynchronize(playerAppID);
	} else
		playerID = (CFStringRef) [NSString stringWithString:(NSString *)stmp];
	CFRelease(stmp);
	[playerName setStringValue:(NSString *)playerID];
		// CFRelease(playerID);
		// CFRelease(name);
	
	name = [NSString stringWithFormat:@"archiver-%@-Name", myUniqueID];
	stmp = (CFStringRef)CFPreferencesCopyAppValue((CFStringRef)name, archiverAppID);
	CFStringRef archiverID;
	if (stmp == nil) {
		NSString *str = NSFullUserName();
		if (str == nil)
			archiverID = (CFStringRef) @" Archiver";
		else
			archiverID = (CFStringRef) [NSString stringWithFormat:@"%@'s Archiver", str];
		
		CFPreferencesSetAppValue((CFStringRef)name, archiverID, archiverAppID);
		stmp = CFUUIDCreateString(nil, uuidObj);
		NSString *uidStr = (NSString *)stmp; // [(NSString*)stmp substringToIndex:8];
		CFPreferencesSetAppValue((CFStringRef)[NSString stringWithFormat:@"archiver-%@", myUniqueID], uidStr, archiverAppID);
		CFPreferencesAppSynchronize(archiverAppID);
	} else
		archiverID = (CFStringRef)[NSString stringWithString:(NSString *)stmp];
	CFRelease(stmp);
	[archiverName setStringValue:(NSString *)archiverID];
		// CFRelease(archiverID);
	
	CFRelease(uuidObj);
}

- (IBAction)changestreamernameAction:(id)sender {
	NSString *name = [NSString stringWithFormat:@"streamer-%@-Name", myUniqueID];
	
	if ([[sender stringValue] isEqualToString:@""]) {
		CFStringRef streamID = (CFStringRef)CFPreferencesCopyAppValue((CFStringRef)name, streamerAppID);
		[streamerName setStringValue:(NSString *)streamID];
		CFRelease(streamID);
	} else {
		CFPreferencesSetAppValue((CFStringRef)name, [sender stringValue], streamerAppID);
		CFPreferencesAppSynchronize(streamerAppID);
	}
	
	CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
	CFNotificationCenterPostNotification(center, CFSTR("Preferences Changed"), streamerAppID, NULL, TRUE);

}
- (IBAction)changeplayernameAction:(id)sender {
	NSString *name = [NSString stringWithFormat:@"player-%@-Name", myUniqueID];
	
	if ([[sender stringValue] isEqualToString:@""]) {
		CFStringRef playerID = (CFStringRef)CFPreferencesCopyAppValue((CFStringRef)name, playerAppID);
		[playerName setStringValue:(NSString *)playerID];
		CFRelease(playerID);
	} else {
		CFPreferencesSetAppValue((CFStringRef)name, [sender stringValue], playerAppID);
		CFPreferencesAppSynchronize(playerAppID);
	}
	
	CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
	CFNotificationCenterPostNotification(center, CFSTR("Preferences Changed"), playerAppID, NULL, TRUE);
	
}
- (IBAction)changearchivernameAction:(id)sender {
	NSString *name = [NSString stringWithFormat:@"archiver-%@-Name", myUniqueID];
	if ([[sender stringValue] isEqualToString:@""]) {
		CFStringRef archiverID = (CFStringRef)CFPreferencesCopyAppValue((CFStringRef)name, archiverAppID);
		[archiverName setStringValue:(NSString *)archiverID];
		CFRelease(archiverID);
	} else {
		CFPreferencesSetAppValue((CFStringRef)name, [sender stringValue], archiverAppID);
		CFPreferencesAppSynchronize(archiverAppID);
	}
	
	CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
	CFNotificationCenterPostNotification(center, CFSTR("Preferences Changed"), archiverAppID, NULL, TRUE);
	
}
- (IBAction)changelocationdisclosureAction:(id)sender {
	if ([sender state]) 
		NSLog(@"Disclose location!!");
}

- (void)didUnselect {
	CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
	CFNotificationCenterPostNotification(center, CFSTR("Preferences Changed"), streamerAppID, NULL, TRUE);
		// NSLog(@"Our prefs panel is now un-selected.");
}

- (void)confirmSheetDidEnd:(NSWindow*)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
#pragma unused(contextInfo)
	[sheet orderOut:self];	// hide the sheet
    
		// decide how we want to unselect
	if (returnCode == NSAlertDefaultReturn)
		[self replyToShouldUnselect:NSUnselectNow];
	else
		[self replyToShouldUnselect:NSUnselectCancel];
}
- (NSPreferencePaneUnselectReply)shouldUnselect {
	return NSUnselectNow;
}
@end
