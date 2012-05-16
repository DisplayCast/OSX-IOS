// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "AppController.h"

#include <zlib.h>

@interface AppController ()
- (void) setupPicker;
- (void) presentPicker:(NSString *)name;
@end

#pragma mark -
@implementation AppController

- (void) _showAlert:(NSString *)title {
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:@"Check your networking configuration." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alertView show];
	[alertView release];
}

id _self;
CGFloat scale = 1.0;
int pWidth = -1, pHeight = -1;   // Previous width and height to detect and perhaps 
unsigned int pmaskX = -1, pmaskY = -1, pmaskWidth = -1, pmaskHeight = -1;
UInt8 *updateData = NULL, *tmpUpdateData = NULL;
UInt32 *winData = NULL;
static UIImageView *view = NULL;

#ifdef USE_CONTROLLER
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    
    return interfaceOrientation == UIInterfaceOrientationPortrait || interfaceOrientation == UIInterfaceOrientationLandscapeLeft || interfaceOrientation == UIInterfaceOrientationLandscapeRight || interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown;
}
#endif

- (void) applicationDidFinishLaunching:(UIApplication *)application {
#pragma unused(application)

    // Remain active as long as the app is running
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
	//Create a full-screen window
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
	//Show the window
	[_window makeKeyAndVisible];
	_self = self;
    
	[self setupPicker];
}

- (void) setupPicker {
#ifdef PLAYERIOS_USE_REMOTE_CONTROL
	[_server release];
	_server = nil;
#endif /* PLAYERIOS_USE_REMOTE_CONTROL */
	
	[_inStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_inStream release];
	_inStream = nil;

	[_outStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_outStream release];
	_outStream = nil;
    
    [self destroyViewer];

    // I am not convinced that a personal device such as iphone/ipad should allow remote users to send streams its way.
    // If we need that, then we need to create and accept remote control commands
#ifdef PLAYERIOS_USE_REMOTE_CONTROL
	_server = [TCPServer new];
	[_server setDelegate:self];
	NSError *error = nil;
	if(_server == nil || ![_server start:&error]) {
		if (error == nil) {
			NSLog(@"Failed creating server: Server instance is nil");
		} else {
		NSLog(@"Failed creating server: %@", error);
		}
		[self _showAlert:@"Failed creating server"];
		return;
	}
	
	//Start advertising to clients, passing nil for the name to tell Bonjour to pick use default name
	if(![_server enableBonjourWithDomain:BONJOUR_DOMAIN applicationProtocol:PLAYER name:@"UUID"]) {
		[self _showAlert:@"Failed advertising server"];
		return;
	}
#endif /* PLAYERIOS_USE_REMOTE_CONTROL */
    
	[self presentPicker:nil];
}

- (void) presentPicker:(NSString *)name {
#pragma unused(name)
    if (_viewer)
        [self destroyViewer];
        
	if (! _picker) {
		_picker = [[streamerPicker alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame] type:STREAMER];
		_picker.delegate = self;
	}
	_picker.streamerName = @"Choose streamer";
	[_picker.svc.tableView deselectRowAtIndexPath:[_picker.svc.tableView indexPathForSelectedRow] animated:NO];

	if (! _picker.superview)
		[_window addSubview:_picker];
}

- (void) destroyPicker {
	[_picker removeFromSuperview];
	[_picker release];
	_picker = nil;
}

- (void) presentViewer:(UIImageView *)view {
#pragma unused(view)
	if (! _viewer) {
		_viewer = [[streamerViewer alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        
        // The order - delegate first and then the zoomscale is important!!
        // http://stackoverflow.com/questions/3848268/uiscrollview-doesnt-pan-until-after-zoom-user-action
		_viewer.delegate = self;
        
        //Set Zooming Prefs
        _viewer.minimumZoomScale = 0.1; // scrollView.frame.size.width / width; // CGImageGetWidth(image.CGImage)/320;
        _viewer.maximumZoomScale = 4.0;
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
			_viewer.zoomScale = 1.0 / [[UIScreen mainScreen] scale];
		else
			_viewer.zoomScale = 1.0;
        _viewer.bouncesZoom = YES;
        _viewer.bounces = YES;
	}
    
    // [_viewer setContentSize: [[view image] size]];
    // [_viewer setDelegate:self];
    
	if (! _viewer.superview.superview)
		[_window addSubview:_viewer.superview];
}

- (void) destroyViewer {
	[_viewer.superview removeFromSuperview];
    [_viewer release];
	_viewer = nil;
}

- (void) dealloc {
	[_inStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	[_inStream release];
    
	[_outStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	[_outStream release];
    
#ifdef PLAYERIOS_USE_REMOTE_CONTROL
	[_server release];
#endif /* PLAYERIOS_USE_REMOTE_CONTROL */
	[_picker release];
    [_viewer release];
	[_window release];
	
    if (updateData != NULL)
        free(updateData);
    if (tmpUpdateData != NULL)
        free(tmpUpdateData);
    if (winData != NULL)
        free(winData);
    
	[super dealloc];
}

// If we display an error or an alert that the remote disconnected, handle dismissal and return to setup
- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
#pragma unused(alertView,buttonIndex)
	[self setupPicker];
}

// Displaycast doesnt actually send anything to the streamer
- (void) send:(const uint8_t)message {
	if (_outStream && [_outStream hasSpaceAvailable])
		if([_outStream write:(const uint8_t *)&message maxLength:sizeof(const uint8_t)] == -1)
			[self _showAlert:@"Failed sending data to peer"];
}

#if 0
- (void) activateView:(UIImageView *)view {
	// [self send:[view tag] | 0x80];
}

- (void) deactivateView:(UIImageView *)view {
	// [self send:[view tag] & 0x7f];
}
#endif /* 0 */

- (void) openStreams {
	_inStream.delegate = self;
	[_inStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_inStream open];
    
	_outStream.delegate = self;
	[_outStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[_outStream open];
}

- (void) streamerPickerViewController:(streamerPickerViewController *)svc didResolveInstance:(NSNetService *)netService {
#pragma unused(svc)
	if (! netService) {
		[self setupPicker];
		return;
	}

    NSLog(@"Connecting to %@", [netService name]);
	// note the following method returns _inStream and _outStream with a retain count that the caller must eventually release
	if (![netService getInputStream:&_inStream outputStream:&_outStream]) {
		NSLog(@"Failed to connect");
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

		[self _showAlert:@"Failed connecting to server"];
		return;
	}

	[self openStreams];
}
@end

#pragma mark -
@implementation AppController (NSStreamDelegate)

bool maxZoom = false;
- (void)handleTap:(UITapGestureRecognizer *)sender {
#pragma unused(sender)
    if (maxZoom)
        _viewer.zoomScale  = _viewer.minimumZoomScale;
    else
        _viewer.zoomScale = _viewer.maximumZoomScale;
    maxZoom = !maxZoom;
    
    // NSLog(@"Tap recognized"); // handling code
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStatePossible) {
        // [self setupPicker];
        [self presentPicker:nil];
    }
}

- (void) handlePinch:(UIPinchGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        if ([sender scale] != 0.0) {
            NSLog(@"Pinched: %f", [sender scale]);

            scale = scale / [sender scale];
        }
    }
}

- (void) handlePan:(UIPanGestureRecognizer *) sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        UIImageView *view = nil;
        NSArray *array = [_window subviews];
        for (id object in array) {
            if ([object isKindOfClass:[UIImageView class]]) {
                view = (UIImageView *)object;
                
                break;
            }
        }
        
        CGPoint pan = [sender translationInView:view];
        NSLog(@"Panned: %fx%f", pan.x, pan.y);
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
#pragma unused(scrollView)
    
    return view;
}

- (void)startViewer:(UIImageView *)view {
    [self destroyPicker];
    [self presentViewer:view];

    [_viewer addSubview:view];
    [_window addSubview:_viewer.superview];
    
    _viewer.autoresizesSubviews = YES;
    _viewer.superview.autoresizesSubviews = YES;
}

#if 0
NSArray *array = [window subviews];
for (id object in array) {
    if ([object isKindOfClass:[UIImageView class]]) {
        UIImageView *tmpView = (UIImageView *)object;
        
        [tmpView removeFromSuperview];
        [tmpView release];
        
        break;
    }
    if ([object isKindOfClass:[UIScrollView class]]) {
        UIScrollView *tmpScrollView = (UIScrollView *)object;
        
        [tmpScrollView removeFromSuperview];
        [tmpScrollView release];
        
        break;
    }
    NSLog(@"Huh: %@", object);
}
#endif /* 0 */

#if 0
UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]];
[scrollView setContentSize: [image size]];

//Set ScrollView Appearance
[scrollView setBackgroundColor:[UIColor blackColor]];
scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;

//Set Scrolling Prefs
scrollView.bounces = YES;
scrollView.delegate = _self;
scrollView.clipsToBounds = YES; // default is NO, we want to restrict drawing within our scrollview
[scrollView setCanCancelContentTouches:NO];
[scrollView setScrollEnabled:YES];

//Set Zooming Prefs
scrollView.maximumZoomScale = 3.0;
scrollView.minimumZoomScale = scrollView.frame.size.width / width; // CGImageGetWidth(image.CGImage)/320;
scrollView.bouncesZoom = YES;
scrollView.zoomScale = scrollView.minimumZoomScale;
scrollView.bounces = YES;
scrollView.autoresizesSubviews = YES;

[scrollView addSubview:view];
[window addSubview:scrollView];
#endif

#if 0
UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:_self action:@selector(handlePinch:)];
[view addGestureRecognizer:pinchRecognizer];
[pinchRecognizer release];

UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:_self action:@selector(handlePan:)] ;
[window addGestureRecognizer:panRecognizer];
[panRecognizer release];
#endif
    
void displayWin(UIWindow *window, int width, int height, int maskX, int maskY, int maskWidth, int maskHeight, UInt32 *buf) {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef bitmapData = CGDataProviderCreateWithData(NULL, buf, width * height * sizeof(UInt32), NULL /*releaseProvider*/);
    CGImageRef myImage = CGImageCreate(width, 
                                       height,
                                       sizeof(UInt8) * 8,
                                       sizeof(UInt32) * 8,
                                       width * sizeof(UInt32),
                                       colorSpace,
                                       (/* kCGImageAlphaNoneSkipFirst */ kCGImageAlphaPremultipliedFirst |kCGBitmapByteOrder32Host),
                                       bitmapData,
                                       NULL,
                                       false,
                                       kCGRenderingIntentDefault);

    // UIImage *image = [UIImage imageWithCGImage:myImage scale:scale orientation:UIImageOrientationRight];
    // UIImage *image = [UIImage imageWithCGImage:myImage scale:1.0 orientation:[[UIDevice currentDevice] orientation]];
    UIImage *image = [UIImage imageWithCGImage:myImage];
    
    // Now create a UIImageView, add it inside a UIScrollView, add the UIScrollView to the window and off we go!!
    // Remove the previous UIView and add a new one
    if (view == NULL) {
        view = [[[UIImageView alloc] initWithImage:image] retain];
        // view.userInteractionEnabled = YES;
        view.autoresizesSubviews = YES;

        // view.clipsToBounds = NO;
        // [view setFrame:[[UIScreen mainScreen] bounds]];
        // view.contentMode = UIViewContentModeRedraw | UIViewContentModeScaleAspectFit;
        // view.contentMode = UIViewContentModeScaleAspectFit;
        
        view.contentMode =  (UIViewContentModeCenter | UIViewContentModeScaleAspectFit | UIViewContentModeRedraw);
        view.autoresizingMask =  (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin);
        
        [_self startViewer:view];
        
        NSArray *gestures = [window gestureRecognizers];
        if ([gestures count] == 0) {
            UILongPressGestureRecognizer *longRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:_self action:@selector(handleLongPress:)];
            longRecognizer.numberOfTapsRequired = 0;
            longRecognizer.numberOfTouchesRequired = 1;
            longRecognizer.minimumPressDuration = 1.0;
            [window addGestureRecognizer:longRecognizer];
            [longRecognizer release];
            
            UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:_self action:@selector(handleTap:)];
            tapRecognizer.numberOfTapsRequired = 2;
            [window addGestureRecognizer:tapRecognizer];
            [tapRecognizer release];
        }
        window.autoresizesSubviews = YES;

        [window makeKeyAndVisible];
    } else
        [view setImage:image];

    if (! ((maskX == 0) && (maskY == 0) && (maskWidth == width) && (maskHeight == height)) )
        NSLog(@"Need to take care of masking");

    CGImageRelease(myImage);
    CGDataProviderRelease(bitmapData);
    CGColorSpaceRelease(colorSpace);
}

void drawWin(UInt32 *winData, int width, int height, int x, int y, int w, int h, UInt32 *buf) {
#pragma unused(height)
    
    for (int iy = 0; iy < h; iy++) {
        for (int ix = 0; ix < w; ix++) {
            if (*buf != 0x00FFFFFF) {
                int indx = ((int) width * (y + iy)) + (x + ix);
                
                *(winData + indx) = *buf;
            }
            buf++;
        }
    }
}

boolean_t uncompressBuffer(UIWindow *window, UInt8 *receiveBuf, UInt32 pktSize) {
    boolean_t retValue = true;
    
    z_stream strm;
    UInt32 out[5];  // space for the first five integers
    unsigned int width, height, x, y, w, h;
    unsigned int maskX, maskY, maskWidth, maskHeight;
    
    // First, uncompress the first five integers which repreent the width, height, maskX, maskY, maskW, maskH, x, y, w and h
    /* allocate inflate state */
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.avail_in = 0;
    strm.next_in = Z_NULL;
    if (inflateInit(&strm) != Z_OK)
        exit(1);
    
    strm.avail_in = (uInt) pktSize;
    strm.next_in = receiveBuf;
    int flush = Z_NO_FLUSH; // Z_BLOCK;
    
    strm.avail_out = sizeof(out);
    strm.next_out = (unsigned char *)out;
    switch (inflate(&strm, flush)) {
        case Z_STREAM_ERROR:
            NSLog(@"HEADER Z_STREAM_ERROR %d", strm.avail_out);
            (void)inflateEnd(&strm);
            retValue = false;
            break;
            
        case Z_NEED_DICT:
            NSLog(@"HEADER Z_NEED_DICT");
            (void)inflateEnd(&strm);
            retValue = false;
            break;
            
        case Z_DATA_ERROR:
            NSLog(@"HEADER Z_DATA_ERROR %ld", pktSize);
            (void)inflateEnd(&strm);
            retValue = false;
            break;
            
        case Z_MEM_ERROR:
            NSLog(@"HEADER Z_MEM_ERROR");
            (void)inflateEnd(&strm);
            retValue = false;
            break;
    }
    if (retValue == false)
        return retValue;
    
    width = ntohl(out[0])>>16;
    height = ntohl(out[0])&0xffff;
    maskX = ntohl(out[1])>>16;
    maskY = ntohl(out[1])&0xffff;
    maskWidth = ntohl(out[2])>>16;
    maskHeight = ntohl(out[2])&0xffff;
    x = ntohl(out[3])>>16;
    y = ntohl(out[3])&0xffff;
    w = ntohl(out[4])>>16;
    h = ntohl(out[4])&0xffff;
    
    assert(w<=width);
    assert(h<=height);
    
    // If this is the first time, then create a new window to show 
    if (((int) width !=  pWidth) || ((int) height != pHeight)) {
        if (pWidth != -1) {
            NSLog(@"Dynamically changing window size not support yet %dx%d from %dx%d", width, height, pWidth, pHeight);
            return false;
        } else
            NSLog(@"Setting window of size %dx%d", width, height);
        pWidth = width;
        pHeight = height;
        // winData = calloc(width * height, sizeof(UInt32));
        updateData = malloc(width * height * sizeof(UInt32));   // Allocate once and reuse
        tmpUpdateData = malloc(width * height * sizeof(UInt32));    // Needed for bitmap encoding
        
#if 0
        // Attempt to make the image fit into our screen
        CGRect winSize = [window bounds];
        CGFloat wScale = width / winSize.size.width;
        CGFloat hScale = height / winSize.size.height;
        scale = (wScale > hScale) ? wScale : hScale;
#endif /* 0 */
    }
    
    if (! ((pmaskX == maskX) && (pmaskY == maskY) && (pmaskWidth == maskWidth) && (pmaskHeight == maskHeight)) ) {
        if (winData == NULL)
            winData = malloc(width * height * sizeof(UInt32));
        else
            bzero(winData, width * height * sizeof(UInt32));
        displayWin(window, width, height, maskX, maskY, maskWidth, maskHeight, winData);
        
        pmaskX = maskX;
        pmaskY = maskY;
        pmaskWidth = maskWidth;
        pmaskHeight = maskHeight;
    }
    
    /* run inflate() on input until output buffer not full */
    // UInt8 *updateData = malloc(w * h * sizeof(UInt32));
    unsigned long uncompressed = 0;
    // UInt8 *updPtr = updateData;
    int sz;
    do {
        sz = (int) ((w * h * sizeof(UInt32)) - uncompressed);
        strm.avail_out = sz;
        strm.next_out = tmpUpdateData + uncompressed;
        
        int ret_value = inflate(&strm, flush);
        switch (ret_value) {
            case Z_STREAM_ERROR:
                if (sz != (int) strm.avail_out)
                    NSLog(@"DATA Z_STREAM_ERROR %d", (int) ((w * h * sizeof(UInt32)) - uncompressed));
                break;
                
            case Z_NEED_DICT:
                NSLog(@"DATA Z_NEED_DICT");
                break;
                
            case Z_DATA_ERROR:
                if (sz != (int) strm.avail_out)
                    NSLog(@"DATA Z_DATA_ERROR %d", (int) ((w * h * sizeof(UInt32)) - uncompressed));
                break;
                
            case Z_MEM_ERROR:
                NSLog(@"DATA Z_MEM_ERROR");
                break;
        }
        uncompressed += strm.avail_out;
        // } while (uncompressed < (w * h * sizeof(UInt32)));
    } while (sz != (int) strm.avail_out);
    
    /* clean up and return */
    (void)inflateEnd(&strm);
    
    // Now perform bitmap encoding's decoding
    int bmStart = 0;
    int srcStart = w*h;
    
    assert(tmpUpdateData != NULL);
    
    for (unsigned int j = 0; j < h; j++) {
        for (unsigned int i = 0; i < w; i++) {
            if (tmpUpdateData[bmStart] == 0xFF) {
                updateData[bmStart * sizeof(UInt32)] = tmpUpdateData[srcStart++];
                updateData[bmStart * sizeof(UInt32) + 1] = tmpUpdateData[srcStart++];
                updateData[bmStart * sizeof(UInt32) + 2] = tmpUpdateData[srcStart++];
                updateData[bmStart * sizeof(UInt32) + 3] = 0xFF;
            } else {
                updateData[bmStart * sizeof(UInt32)] = 0xFF;
                updateData[bmStart * sizeof(UInt32) + 1] = 0xFF;
                updateData[bmStart * sizeof(UInt32) + 2] = 0xFF;
                updateData[bmStart * sizeof(UInt32) + 3] = 0x00;
            }
            bmStart++;
        }
    }
    
    if (winData == NULL) {
        assert((w == width) && (h == height));
		assert((width > 0) && (height > 0));
        
        winData = malloc(width * height * sizeof(UInt32));
        assert(updateData != NULL);
        memcpy(winData, updateData, width * height * sizeof(UInt32));

		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    } else {
        // Overlay the update onto my view of the frame
        drawWin(winData, width, height, x, y, w, h, (UInt32 *) updateData);
    }
    
    // Now, display my view of the frame
    displayWin(window, width, height, maskX, maskY, maskWidth, maskHeight, winData);
    
    return retValue;
}

- (void) stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    UInt8 *receiveBuf = NULL;
    
	switch(eventCode) {
		case NSStreamEventOpenCompleted: {
			[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
            if (stream == _inStream) {
                [self destroyPicker];
                
                // Reset all window parameters
                pWidth = pHeight = pmaskX = pmaskY = pmaskWidth = pmaskHeight = -1;
                scale = 1.0;
                
                if (updateData != NULL) {
                    free(updateData);
                    updateData = NULL;
                }
                
                if (tmpUpdateData != NULL) {
                    free(tmpUpdateData);
                    tmpUpdateData = NULL;
                }
                
                if (winData != NULL) {
                    free(winData);
                    winData = NULL;
                }
            }
            
            if (view != nil) {
                [view release];
                view = nil;
            }
			break;
		}
		case NSStreamEventHasBytesAvailable: {
			if (stream == _inStream) {
                UInt32 pktSize, len;
                
                len = [_inStream read:(UInt8 *)&pktSize maxLength:sizeof(UInt32)];
                if (len != sizeof(UInt32))
                    break;
                
                // Now receive this much data - freeing memory from prior loops
                if (receiveBuf)
                    free(receiveBuf);
                receiveBuf = malloc(pktSize);
                
                len = 0;
                while ((UInt32) len < pktSize) {
                    ssize_t recvLen = [_inStream read:(receiveBuf + len) maxLength:(pktSize - len)];
                    if (recvLen <= 0)
                        break;
                    len += recvLen;
                }
                if (len != pktSize)
                    break;
                
                if (uncompressBuffer(_window, receiveBuf, pktSize) == false)
                    break;
			}
			break;
		}
		case NSStreamEventErrorOccurred: {
			[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
            [self presentPicker:nil];
			break;
		}
		case NSStreamEventEndEncountered: {
			[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
            [self presentPicker:nil];
			break;
		}
	}
}

@end


#pragma mark -
@implementation AppController (TCPServerDelegate)

#ifdef PLAYERIOS_USE_REMOTE_CONTROL
- (void) serverDidEnableBonjour:(TCPServer *)server withName:(NSString *)string {
#pragma unused(server)
	[self presentPicker:string];
}

- (void)didAcceptConnectionForServer:(TCPServer *)server inputStream:(NSInputStream *)istr outputStream:(NSOutputStream *)ostr {
	if (_inStream || _outStream || server != _server)
		return;
	
	[_server release];
	_server = nil;
	
	_inStream = istr;
	[_inStream retain];
	_outStream = ostr;
	[_outStream retain];
	
	[self openStreams];
}
#endif /* PLAYERIOS_USE_REMOTE_CONTROL */
@end
