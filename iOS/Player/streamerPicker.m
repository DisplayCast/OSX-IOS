// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "streamerPicker.h"

#define kOffset 5.0

@interface streamerPicker ()
@property (nonatomic, retain, readwrite) UILabel *streamerNameLabel;
@end

@implementation streamerPicker

@synthesize svc = _svc;
@synthesize streamerNameLabel = _streamerNameLabel;

- (id)initWithFrame:(CGRect)frame type:(NSString*)type {
	if ((self = [super initWithFrame:frame])) {
		// add autorelease to the NSNetServiceBrowser to release the browser once the connection has been
		// established. An active browser can cause a delay in sending data.
		// <rdar://problem/7000938>
		self.svc = [[[streamerPickerViewController alloc] initWithTitle:nil] autorelease];
		self.svc.snapshotDownloadsInProgress = [NSMutableDictionary dictionary];
		self.svc.streamers = [NSMutableDictionary dictionary] ;
		[self.svc searchForServicesOfType:type inDomain:BONJOUR_DOMAIN];
		
		self.opaque = YES;
		self.backgroundColor = [UIColor blackColor];

#ifdef PLAYERIOS_USE_STATUSBAR
		// Shiny background!!
        UIImageView* img = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"bg.png"]];
		[self addSubview:img];
		[img release];

		CGFloat runningY = kOffset;
		CGFloat width = self.bounds.size.width - 2 * kOffset;
		
		self.streamerNameLabel = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
		[self.streamerNameLabel setTextAlignment:UITextAlignmentCenter];
		[self.streamerNameLabel setFont:[UIFont boldSystemFontOfSize:18.0]];
		[self.streamerNameLabel setLineBreakMode:UILineBreakModeTailTruncation];
		[self.streamerNameLabel setTextColor:[UIColor whiteColor]];
		[self.streamerNameLabel setShadowColor:[UIColor colorWithWhite:0.0 alpha:0.75]];
		[self.streamerNameLabel setShadowOffset:CGSizeMake(1,1)];
		[self.streamerNameLabel setBackgroundColor:[UIColor clearColor]];
		[self.streamerNameLabel setText:@"Choose Streamer"];
		[self.streamerNameLabel sizeToFit];
		[self.streamerNameLabel setFrame:CGRectMake(kOffset, runningY, width, self.streamerNameLabel.frame.size.height)];
		[self.streamerNameLabel setText:@""];
		[self addSubview:self.streamerNameLabel];
		
		runningY += self.streamerNameLabel.bounds.size.height + kOffset * 2;
		
		[self.svc.view setFrame:CGRectMake(0, runningY, self.bounds.size.width, self.bounds.size.height - runningY)];
#endif /* PLAYERIOS_USE_STATUSBAR */
		[self addSubview:self.svc.view];
		
	}

	return self;
}

- (void)dealloc {
	// Cleanup any running resolve and free memory
	// [self.svc release]; - this is autoreleased
	// [self.streamerNameLabel release];
	
	[super dealloc];
}

- (id<streamerPickerViewControllerDelegate>)delegate {
	return self.svc.delegate;
}

- (void)setDelegate:(id<streamerPickerViewControllerDelegate>)delegate {
	[self.svc setDelegate:delegate];
}

- (NSString *)streamerName {
	return self.streamerNameLabel.text;
}

- (void)setStreamerName:(NSString *)string {
	[self.streamerNameLabel setText:string];
}
@end
