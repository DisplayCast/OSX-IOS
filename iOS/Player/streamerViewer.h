// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <UIKit/UIKit.h>

#import "streamerViewerViewController.h"

@interface streamerViewer : UIScrollView <streamerViewerViewControllerDelegate> {
    streamerViewerViewController *_svvc;
}

	// @property (nonatomic, assign) id<streamerViewerViewControllerDelegate> delegate;

// - (void) addImageView:(UIImageView *)view;
@end
