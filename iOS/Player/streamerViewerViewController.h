// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <UIKit/UIKit.h>

@class streamerViewerViewController;

@protocol streamerViewerViewControllerDelegate <NSObject>
@required

@end

@interface streamerViewerViewController : UIViewController <UIScrollViewDelegate> {
@private
	id<streamerViewerViewControllerDelegate> _delegate;
}

@property (nonatomic, assign) id<streamerViewerViewControllerDelegate> delegate;
@end
