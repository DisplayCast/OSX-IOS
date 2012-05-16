// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "streamerViewer.h"
#import "streamerViewerViewController.h"

@interface streamerViewer ()
@property (nonatomic, retain, readwrite) streamerViewerViewController *svvc;
@end

@implementation streamerViewer
	// @synthesize delegate;
@synthesize svvc = _svvc;

- (id)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        //Set ScrollView Appearance
        [self setBackgroundColor:[UIColor blackColor]];
        self.indicatorStyle = UIScrollViewIndicatorStyleWhite;
        
        //Set Scrolling Prefs
        self.clipsToBounds = NO; // default is NO, we want to restrict drawing within our scrollview
        [self setCanCancelContentTouches:NO];
        [self setScrollEnabled:YES];
        
        self.autoresizesSubviews = YES;
        self.contentMode =  (UIViewContentModeCenter | UIViewContentModeRedraw | UIViewContentModeScaleAspectFit);
        self.autoresizingMask =  (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin);
        
        self.svvc = [[[streamerViewerViewController alloc] init] autorelease];
        
        // CGFloat maxDimen = ( self.bounds.size.width > self.bounds.size.height) ? self.bounds.size.width : self.bounds.size.height;
        // [self.svvc.view setFrame:CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height)];
        
        // self.svvc.wantsFullScreenLayout = YES; // GOing fullscreen would mean that the status bar will overlap on the top
        self.svvc.view.autoresizesSubviews = YES;
        
		// [self addSubview:self.svvc.view];
        [self.svvc.view addSubview:self];
    }
    return self;
}

#if 0
- (void) addImageView:(UIImageView *)view {
    // [_svvc.view addSubview:view];
    [self addSubview:view];
    
        /// _svvc.wantsFullScreenLayout = YES;
}
#endif /* 0 */

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
