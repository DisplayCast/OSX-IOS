// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "streamerPickerViewController.h"
#import "streamerPicker.h"
#import "streamerViewerViewController.h"
#import "streamerViewer.h"
#import "TCPServer.h"
#import "Globals.h"

@interface AppController : NSObject <UIApplicationDelegate, UIActionSheetDelegate,
streamerPickerViewControllerDelegate, streamerViewerViewControllerDelegate, UIScrollViewDelegate,
#ifdef PLAYERIOS_USE_REMOTE_CONTROL
TCPServerDelegate,
#endif /* PLAYERIOS_USE_REMOTE_CONTROL */
NSStreamDelegate> {
	UIWindow			*_window;
	streamerPicker		*_picker;
    streamerViewer      *_viewer;
    
#ifdef PLAYERIOS_USE_REMOTE_CONTROL
	TCPServer			*_server;
#endif /* PLAYERIOS_USE_REMOTE_CONTROL */
	NSInputStream		*_inStream;
	NSOutputStream		*_outStream;
	BOOL				_inReady;
	BOOL				_outReady;
}

#if 0
- (void) activateView:(UIImageView *)view;
- (void) deactivateView:(UIImageView *)view;
#endif /* 0 */

// @property (assign) IBOutlet UIScrollView *scrollView;

@end
