// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <UIKit/UIKit.h>
#import <Foundation/NSNetServices.h>

#import "Globals.h"
#import "streamerSnapshotDownloader.h"

@class streamerPickerViewController;

@protocol streamerPickerViewControllerDelegate <NSObject, NSNetServiceBrowserDelegate>
@required
// This method will be invoked when the user selects one of the service instances from the list.
// The ref parameter will be the selected (already resolved) instance or nil if the user taps the 'Cancel' button (if shown).
- (void) streamerPickerViewController:(streamerPickerViewController *)svc didResolveInstance:(NSNetService *)ref;
@end

@interface streamerPickerViewController : UITableViewController <NSNetServiceDelegate, NSNetServiceBrowserDelegate, StreamerSnapshotDownloaderDelegate>{

@private
	id<streamerPickerViewControllerDelegate> _delegate;
	NSMutableArray *_services;
	NSMutableDictionary *snapshotDownloadsInProgress;
	NSMutableDictionary *streamers;
	NSNetServiceBrowser *_netServiceBrowser;
	NSTimer *_timer;

	BOOL _initialWaitOver;
}

@property (nonatomic, assign) id<streamerPickerViewControllerDelegate> delegate;
@property (nonatomic, retain) NSMutableDictionary *snapshotDownloadsInProgress;
@property (nonatomic, retain) NSMutableDictionary *streamers;

- (BOOL)searchForServicesOfType:(NSString *)type inDomain:(NSString *)domain;

- (id)initWithTitle:(NSString *)title;

- (void)appImageDidLoad:(NSIndexPath *)indexPath;

@end
