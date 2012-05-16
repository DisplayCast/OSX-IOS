// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <UIKit/UIKit.h>
#import "streamerPickerViewController.h"

@interface streamerPicker : UIView {

@private
	UILabel *_streamerNameLabel;
	streamerPickerViewController *_svc;
}

@property (nonatomic, assign) id<streamerPickerViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *streamerName;
@property (nonatomic, retain, readwrite) streamerPickerViewController *svc;

- (id)initWithFrame:(CGRect)frame type:(NSString *)type;

@end
