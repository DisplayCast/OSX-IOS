// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Cocoa/Cocoa.h>

#import <Faunus/Faunus.h>
#import <Faunus/Wallet.h>

@interface ArchiverAppDelegate : NSObject <NSStreamDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSWindowDelegate, NSApplicationDelegate> {
	NSArrayController *     _servicesArray;
    
    NSString *              _serviceName;
    
    NSMutableSet *          _services;
    NSArray *               _sortDescriptors;
    
    NSNetServiceBrowser *   _browser;
    NSMutableSet *          _resolvers;
    
    NSMutableSet *          _pendingServicesToAdd;
    NSMutableSet *          _pendingServicesToRemove;
    
    NSMutableSet *          _nsSessions;
	
	AVAssetWriter		*_videoWriter;
	AVAssetWriterInput  *_writerInput;
	
	NSString *myUniqueID;
	
    NSOperationQueue *      _queue;
	NSTimer *_timer;
}

@property (nonatomic, retain) NSTimer *timer;
@property (nonatomic, retain) Faunus *faunus;
@property (nonatomic, retain) NSString *archiverID;

@property (nonatomic, retain, readwrite) IBOutlet NSArrayController *   servicesArray;

@property (nonatomic, retain, readwrite) AVAssetWriter *videoWriter;
@property (nonatomic, retain, readwrite) AVAssetWriterInput *writerInput;
	// Actions

- (IBAction)tableRowClickedAction:(id)sender;

	// The user interface uses Cocoa bindings to set itself up based on the following 
	// KVC/KVO compatible properties.

@property (nonatomic, retain, readonly ) NSMutableSet *     services;
@property (nonatomic, retain, readonly ) NSArray *          sortDescriptors;
@property (nonatomic, copy,   readonly ) NSString *         serviceName;
@end
