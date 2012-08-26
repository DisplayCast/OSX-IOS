// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Cocoa/Cocoa.h>

#import <Faunus/Faunus.h>
#import <Faunus/Wallet.h>

#import "PlayerListing.h"
#import "MenuEntry.h"
#import "Globals.h"

@interface PlayerAppDelegate : NSObject <NSStreamDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSWindowDelegate> {
    NSArrayController *     _servicesArray;
    
    NSString *              _serviceName;
    
    NSMutableSet *          _services;
    NSArray *               _sortDescriptors;
    
    NSNetServiceBrowser *   _browser;
    
    NSMutableSet *          _pendingServicesToAdd;
    NSMutableSet *          _pendingServicesToRemove;
    
    NSMutableSet *          _nsSessions;

    NSOperationQueue *      _queue;
    
	NSString *myUniqueID;
	NSString *_playerID;

	NSStatusItem *trayItem;
    
    IBOutlet NSImageView *riv0, *riv1, *riv2, *riv3, *riv4, *riv5, *riv6, *riv7, *riv8, *riv9;

		// Scrollview is a nice addition in Mountain Lion!!
		// IBOutlet NSScrollView *nrsv0, *nrsv1, *nrsv2, *nrsv3, *nrsv4, *nrsv5, *nrsv6, *nrsv7, *nrsv8, *nrsv9;
	
	IBOutlet NSMenu *statusMenu;
	
	IBOutlet NSWindow *chooserWindow;
}

@property (nonatomic, retain, readwrite) IBOutlet NSArrayController *   servicesArray;
@property (assign) IBOutlet NSWindow *rw0;
@property (assign) IBOutlet NSWindow *rw1;
@property (assign) IBOutlet NSWindow *rw2;
@property (assign) IBOutlet NSWindow *rw3;
@property (assign) IBOutlet NSWindow *rw4;
@property (assign) IBOutlet NSWindow *rw5;
@property (assign) IBOutlet NSWindow *rw6;
@property (assign) IBOutlet NSWindow *rw7;
@property (assign) IBOutlet NSWindow *rw8;
@property (assign) IBOutlet NSWindow *rw9;

@property (assign) IBOutlet NSMenu *streamMenu;
@property (assign) IBOutlet NSWindow *chooserWindow;

// Actions

- (IBAction)tableRowClickedAction:(id)sender;

// The user interface uses Cocoa bindings to set itself up based on the following 
// KVC/KVO compatible properties.

@property (nonatomic, retain, readonly ) NSMutableSet *     services;
@property (nonatomic, retain, readonly ) NSArray *          sortDescriptors;
@property (nonatomic, copy,   readonly ) NSString *         serviceName;

@property (retain) NSString *playerID;

@property (nonatomic, retain) Faunus *faunus;

@end
