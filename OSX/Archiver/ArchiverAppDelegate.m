// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <CoreFoundation/CFSocket.h>
#import <AVFoundation/AVFoundation.h>

#import "PlayerListing.h"
#import "ArchiverAppDelegate.h"
#import "OCR.h"
#import "GetUniqueID.h"
#import "Globals.h"

#include <sys/types.h>  /* for type definitions */
#include <sys/socket.h> /* for socket API calls */
#include <netinet/in.h> /* for address structs */
#include <arpa/inet.h>  /* for sockaddr_in */
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/time.h>
#include <zlib.h>

@interface ArchiverAppDelegate () <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSWindowDelegate, NSURLConnectionDelegate>

@property (nonatomic, retain, readwrite) NSNetServiceBrowser *  browser;
@property (nonatomic, retain, readonly ) NSMutableSet *         pendingServicesToAdd;
@property (nonatomic, retain, readonly ) NSMutableSet *         pendingServicesToRemove;
@property (nonatomic, copy,   readwrite) NSString *             serviceName;
@property (nonatomic, copy,   readonly ) NSString *             defaultServiceName;

// forward declarations
- (void)receiveFromService:(NSNetService *)service;
#ifdef OCR
- (void)startOCR:(OCR *)ocr;
#endif /* OCR */

void drawWin(UInt32 *winData, int width, int height, int x, int y, int w, int h, UInt32 *buf);
void receiveData(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);
@end

@implementation ArchiverAppDelegate

@synthesize servicesArray = _servicesArray;
@synthesize browser = _browser;

@synthesize timer = _timer;

NSNetService *netService;
NSMutableData *receivedData;

static NSMutableDictionary *myKeys = NULL;         // Advertise myself using these TXT records

#define NUM_SESSIONS 10
NSNetService *activeNSSessions[NUM_SESSIONS];
bool stopSession[NUM_SESSIONS];
// NSWindow *windows[NUM_SESSIONS];

#pragma mark * Application delegate callbacks
void receiveData(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
#pragma unused(info,type)
    ArchiverAppDelegate *obj = (__bridge ArchiverAppDelegate *)info;
    assert([obj isKindOfClass:[ArchiverAppDelegate class]]);
    NSString *result = @"NotFound";
    
    NSString *command = [[NSString alloc] initWithData:(__bridge NSData *)data encoding:NSUTF8StringEncoding /* NSASCIIStringEncoding */];
    NSArray *array = [command componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *cmd = [array objectAtIndex:0];
    
    if ([cmd isEqualToString:@"SHOW"]) {
        NSString *strm = [array objectAtIndex:1];
        
        NSLog(@"DEBUG: Remote command - Show stream: %@", strm);
        // Search all nsSessions
        boolean_t done = false;
        for (PlayerListing *pl in obj.servicesArray.content) {
            NSNetService *plns = [pl ns];
            NSString *plName = [plns name];
            
            if ([plName isEqualToString:strm]) {
                // First check whether this is a duplicate
                for (int indx = 0; indx < NUM_SESSIONS; indx++) {
                    NSNetService *ns = activeNSSessions[indx];
                    
                    if (ns == nil)
                        continue;
                    
                    if ([[ns name] isEqualToString:plName]) {
                        NSLog(@"DEBUG: Session already active, bringing to front");
                        
                        //						[windows[indx] orderFrontRegardless];
                        
						result = [[NSString alloc] initWithFormat: @"%lu", [activeNSSessions[indx] hash]];
                        done = true;
                        
                        break;
                    }
                }
                
                if (done == false) {
                    NSLog(@"DEBUG: Starting a new session: %@", strm);
                    for (int indx = 0; indx < NUM_SESSIONS; indx++) {
                        if (activeNSSessions[indx] == nil) {
                            activeNSSessions[indx] = plns;
                            
                            [NSThread detachNewThreadSelector:@selector(receiveFromService:) toTarget:obj withObject:plns];
                            done = true;
							result = [[NSString alloc] initWithFormat: @"%lu", [activeNSSessions[indx] hash]];
                            
                            break;
                        }
                    }
                    if (done == false) {
                        NSLog(@"FATAL: Too many sessions");
                        
                        done = true;
                    }
                }
            }
        }
        if (done == false) {
            NSLog(@"DEBUG: Unknown stream: %@", strm);
        }
    }
	
    if ([cmd isEqualToString:@"CLOSE"]) {
        NSString *strm = [array objectAtIndex:1];
        NSUInteger hash = [strm integerValue];
        
        for (int indx = 0; indx < NUM_SESSIONS; indx++) {
			if ([activeNSSessions[indx] hash] == hash) {
                stopSession[indx] = true;
                result = @"SUCCESS";
                
                break;
			}
        }
    }
    
    if ([cmd isEqualToString:@"CLOSEALL"]) {
        for (int indx = 0; indx < NUM_SESSIONS; indx++) 
            stopSession[indx] = true;
        result = @"SUCCESS";
    }
    
    CFSocketSendData(s, address, (__bridge CFDataRef)[result dataUsingEncoding:NSASCIIStringEncoding], 0);
	
    CFSocketInvalidate(s);
    CFRelease(s);
}

static void ListeningSocketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
#pragma unused(type,address,s) 
    ArchiverAppDelegate *obj = (__bridge ArchiverAppDelegate *)info;
    assert([obj isKindOfClass:[ArchiverAppDelegate class]]);
    CFSocketContext CTX = { 0, (__bridge void *)obj, NULL, NULL, NULL };
    
    CFSocketNativeHandle csock = *(CFSocketNativeHandle *)data;
    CFSocketRef sn = CFSocketCreateWithNative(NULL, csock, kCFSocketDataCallBack, receiveData, &CTX);
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, sn, 0);
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    
    CFRelease(source);
    CFRelease(sn);
}

- (IBAction)setPreferences:(id)sender {
#pragma unused(sender)
	
	NSAppleScript *a = [[NSAppleScript alloc] initWithSource:PREFERENCES_APPSCRIPT];
	[a executeAndReturnError:nil];
}

- (void) prefcallbackWithNotification:(NSNotification *)myNotification {
#pragma unused(myNotification)
	[[NSUserDefaults standardUserDefaults] synchronize];
	NSString *myName = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
	[self setServiceName:myName];
}

#pragma mark * Bound properties
// The user interface uses Cocoa bindings to set itself up based on these
// KVC/KVO compatible properties.

- (NSMutableSet *)pendingServicesToAdd {
    if (self->_pendingServicesToAdd == nil) 
        self->_pendingServicesToAdd = [[NSMutableSet alloc] init];
    return self->_pendingServicesToAdd;
}

- (NSMutableSet *)pendingServicesToRemove {
    if (self->_pendingServicesToRemove == nil)
        self->_pendingServicesToRemove = [[NSMutableSet alloc] init];
    return self->_pendingServicesToRemove;
}

- (NSMutableSet *)services {
    if (self->_services == nil) {
        self->_services = [[NSMutableSet alloc] init];
    }
    return self->_services;
}

- (NSOperationQueue *)queue {
    if (self->_queue == nil) {
        self->_queue = [[NSOperationQueue alloc] init];
        assert(self->_queue != nil);
    }
    return self->_queue;
}

- (NSString *)serviceName
{
    if (self->_serviceName == nil) {
        self->_serviceName = [[self defaultServiceName] copy];
        assert(self->_serviceName != nil);
    }
    return self->_serviceName;
}

- (NSString *)defaultServiceName {
    NSString *result;
    
	if (myUniqueID == nil) {
		GetUniqueID *uid = [[GetUniqueID alloc] init];
		
		myUniqueID = [NSString stringWithFormat:@"archiver-%@", [uid GetHWAddress]];
	}
    result = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
    if (result == nil) {
        NSString *str = NSFullUserName();
		
        if (str == nil)
            result = @"Unknown's Archiver";
        else
            result = [NSString stringWithFormat:@"%@'s Archiver", str];
    }
    assert(result != nil);
    return result;
}

- (void)setServiceName:(NSString *)newValue {
    NSLog(@"setServiceName");
    
    if (! [newValue isEqualToString:self->_serviceName]) {
        // [self->_serviceName release];
        self->_serviceName = [newValue copy];
        
        if (self->_serviceName == nil) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
        } else {
            [[NSUserDefaults standardUserDefaults] setObject:self->_serviceName forKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
			
			[myKeys removeObjectForKey:@"name"];
			[myKeys setValue:self->_serviceName forKey:@"name"];
			
			[netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
			
        }
    }
}

- (NSArray *)sortDescriptors {
    if (self->_sortDescriptors == nil) {
        SEL selector;
        
        if ([[NSString string] respondsToSelector:@selector(localizedStandardCompare)])
            selector = @selector(localizedStandardCompare:);
        else
            selector = @selector(localizedCaseInsensitiveCompare:);
        
        self->_sortDescriptors = [[NSArray alloc] 
                                  initWithObjects:[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:selector], nil];
    }
    return self->_sortDescriptors;
}

+ (NSSet *)keyPathsForValuesAffectingIsReceiving {
    return [NSSet setWithObject:@"runningOperations"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &self->_queue) {
        assert([keyPath isEqual:@"isFinished"]);
        
        // IMPORTANT
        // ---------
        // KVO notifications arrive on the thread that sets the property.  In this case that's 
        // always going to be the main thread (because FileReceiveOperation is a concurrent operation 
        // that runs off the main thread run loop), but I take no chances and force us to the 
        // main thread.  There's no worries about race conditions here (one of the things that 
        // QWatchedOperationQueue solves nicely) because AppDelegate lives for the lifetime of 
        // the application.
        
        [self performSelectorOnMainThread:@selector(didFinishOperation:) withObject:object waitUntilDone:NO];
    }
    if (NO) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark * Actions
- (IBAction)tableRowClickedAction:(id)sender {
#pragma unused(sender)
    
    // NSLog(@"Clicked row: %lu selectedRow is: %lu", [sender clickedRow], [[self.servicesArray selectedObjects] count]);
    
    // First, stop activeSessions that are no longer selected
	for (int indx = 0; indx < NUM_SESSIONS; indx++) {
		NSNetService *ns = activeNSSessions[indx];
		
		if (ns == nil)
			continue;
		BOOL found = NO;
		for (PlayerListing *pl in [self.servicesArray selectedObjects]) {
			assert([pl isKindOfClass:[PlayerListing class]]);
			
			NSString *servName = [[pl ns] name];
			if ([[ns name] isEqualToString:servName]) {
				found = YES;
				break;
			}
		}
		if (!found) {
            // NSLog(@"Not found here");
			stopSession[indx] = true;	// The corresponding thread will gracefully shut down
		}
	}
    
    // if ( ([sender clickedRow] >= 0) && [[self.servicesArray selectedObjects] count] != 0) {
    // Next, add items that are newly selected
	for (PlayerListing *pl in [self.servicesArray selectedObjects]) {
        assert([pl isKindOfClass:[PlayerListing class]]);
        
        NSNetService *service = [pl ns];
        assert([service isKindOfClass:[NSNetService class]]);
        
        // First check whether this is a duplicate
        NSString *servName = [service name];
		BOOL found = NO;
        for (int indx = 0; indx < NUM_SESSIONS; indx++) {
            NSNetService *ns = activeNSSessions[indx];
            
            if (ns == nil)
                continue;
            
            if ([[ns name] isEqualToString:servName]) {
				found = YES;
				break;
			}
        }
		
		if (! found) {
			// Next see if there is space
			for (int indx = 0; indx < NUM_SESSIONS; indx++) {
				if (activeNSSessions[indx] == nil) {
					activeNSSessions[indx] = service;
					[NSThread detachNewThreadSelector:@selector(receiveFromService:) toTarget:self withObject:service];
					found = YES;
					
					break;
				}				
			}
			if (! found) {
				NSAlert *alert = [[NSAlert alloc] init];
				[alert setAlertStyle:NSInformationalAlertStyle];
				[alert setMessageText:@"Limit Failure"];
				[alert setInformativeText:@"Currently, we only display 10 sessions"];
                
				return;
			}
        }
    }
}

#pragma mark GraphicsStuff
#if 0
// WTF???
*(dst + 0) = *(buf + 3);  // Alpha
*(dst + 1) = *(buf + 1);  // Red - correct
*(dst + 2) = *(buf + 0);  // Green - correct
*(dst + 3) = *(buf + 2);  // Blue - correct
#endif /* 0 */

void drawWin(UInt32 *winData, int width, int height, int x, int y, int w, int h, UInt32 *buf) {
#pragma unused(height)
    // NSLog(@"DEBUG: drawWin %dx%d %dx%d %dx%d", width, height, x, y, w, h);
    if (buf != NULL) {
        for (int iy = 0; iy < h; iy++) {
            for (int ix = 0; ix < w; ix++) {
                if (*buf != 0x00FFFFFF) {
                    unsigned int indx = (width * (y + iy)) + (x + ix);
                    *(winData + indx) = *buf;
                }
                buf++;
            }
        }
    }
}

#pragma mark Runs as a thread, processing data from a particular streamer
- (void)updateKey:(AVAssetWriter *)videoWriter andNSNetService: (NSNetService *)ns {
    // NSLog(@"Window state changed");
    NSString *archiverID = [[NSUserDefaults standardUserDefaults] stringForKey:myUniqueID];
    NSString *session = [[NSString alloc] initWithFormat:@"%@ %@", [ns name], archiverID];
    NSString *myID = [[NSString alloc] initWithFormat:@"%lu", [videoWriter hash]];
    
    [myKeys removeObjectForKey:myID];
    [myKeys setValue:session forKey:myID];
    
    [netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
}

#ifdef OCR
- (void)startOCR:(OCR *)ocr {
    //	NSLog(@"Settig up a timer");
    // NSTimer *nst = [[NSTimer timerWithTimeInterval:(30.0) target:self selector:@selector(performOCR:) userInfo:ocr repeats:YES] retain];
    // [[NSRunLoop currentRunLoop] addTimer:nst forMode:NSDefaultRunLoopMode]; 
    
    // - (void)performOCR:(NSTimer*)theTimer {
	
    //	if ([theTimer isValid]) {
    // OCR *ocr = (OCR *)[theTimer userInfo];
	NSString *path = [[NSString alloc] initWithFormat: @"%@/", [ocr outputPath]];
	NSString *ocrPath = [NSHomeDirectory() stringByAppendingPathComponent:path];
	mkdir([ocrPath UTF8String], 0755);
	
	while (![ocr isDone]) {
		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
		CGDataProviderRef bitmapData = CGDataProviderCreateWithData(NULL, [ocr data], [ocr width] * [ocr height] * sizeof(UInt32), NULL /*releaseProvider*/);
		CGImageRef myImage = CGImageCreate([ocr width], 
										   [ocr height],
										   sizeof(UInt8) * 8,
										   sizeof(UInt32) * 8,
										   [ocr width] * sizeof(UInt32),
										   colorSpace,
										   (/* kCGImageAlphaNoneSkipFirst */ kCGImageAlphaPremultipliedFirst |kCGBitmapByteOrder32Host),
										   bitmapData,
										   NULL,
										   false,
										   kCGRenderingIntentDefault);
		NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:myImage];
		NSImage *image = [[NSImage alloc] init];
		[image addRepresentation:bitmapRep];
        
        CGColorSpaceRelease(colorSpace);
		CGDataProviderRelease(bitmapData);
        CGImageRelease(myImage);
        
		NSString *ocrText = [[NSString alloc] initWithFormat:@"%@/%f", ocrPath, -[[ocr timeStart] timeIntervalSinceNow]];
        
#ifdef ARCHIVER_TESSERACT_OCR
		NSString *imgFile = [[NSString alloc] initWithFormat:@"/tmp/%lu.tiff", [ocr hash]];
		NSSize sz = [image size];
		NSImage *resizedImage = [[NSImage alloc] initWithSize:NSMakeSize(sz.width*4.0, sz.height*4.0)];
		
		[resizedImage lockFocus];
		[image drawInRect:NSMakeRect(0.0, 0.0, sz.width*4.0, sz.height*4.0) fromRect:NSMakeRect(0.0, 0.0, sz.width, sz.height) operation:NSCompositeSourceOver fraction:1.0];
		[resizedImage unlockFocus];
		[[resizedImage TIFFRepresentation] writeToFile:imgFile atomically:YES];
        
		char cmd[1024];
		sprintf(cmd, "/usr/local/bin/tesseract \"%s\" \"%s\" > /dev/null 2>&1", [imgFile UTF8String], [ocrText UTF8String]);
		system(cmd);
#endif /* ARCHIVER_TESSERACT_OCR */
        
#ifdef ARCHIVER_MS_XCLOUD_OCR
		NSString *boundary = @"----DISPLAYCAST";
        // laurent2.xcloud.fxpal.net
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://192.168.25.102:80/"] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
		[request setHTTPMethod:@"POST"];
		
		NSString *contentType = [NSString stringWithFormat:@"multipart/form-fata, boundary=%@", boundary];
		[request setValue:contentType  forHTTPHeaderField:@"Content-type"];
		
		NSMutableData *postBody = [NSMutableData data];
		[postBody appendData:[[NSString stringWithFormat:@"--%@\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
		[postBody appendData:[@"Content-Disposition: form-data; name=\"upfile\"; filename=\"filename.tiff\"\n" dataUsingEncoding:NSUTF8StringEncoding]];
		[postBody appendData:[@"Content-Type: image/tiff\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
		[postBody appendData:[NSData dataWithData:[image TIFFRepresentation]]];
		[postBody appendData:[[NSString stringWithFormat:@"\n--%@--\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
		
		[request setHTTPBody:postBody];
		
#undef ASYNC
#ifdef ASYNC
		NSLog(@"Sending asynchronous request");
		NSURLConnection *connection = [[[NSURLConnection alloc] initWithRequest:request delegate:self] autorelease];
		if (connection) {
			receivedData = [[NSMutableData data] retain];
		}
#else
		NSLog(@"Okay, sending synchronous lookup");
		
		NSURLResponse *urlResponse = nil;
		NSError *error;
		NSData *response = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&error];
		if (response == nil) {
			NSLog(@"Failure: %@", error);
		} else {
			NSLog(@"Success: %@", urlResponse);
		}
#endif /* ASYNC */
		
#endif /* ARCHIVER_MS_XCLOUD_OCR */
		
        // [image release];
		[NSThread sleepForTimeInterval:30.0];
	}
}
#endif /* OCR */

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
#pragma unused(response,connection)
	[receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
#pragma unused(connection)
	[receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
#pragma unused(connection,error)
    // [connection release];
    // [receivedData release];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
#pragma unused(connection)
	NSLog(@"Yeah, got something: %lu", [receivedData length]);
	NSLog(@"Looks like: %@", [NSString stringWithFormat:@"%@", receivedData]);
    
    // [connection release];
    // [receivedData release];
}

#pragma mark -
#pragma mark * The main displaycast functionality. Archive the streamer
- (void)receiveFromService:(NSNetService *)ns {
    assert(ns != nil);
    
    AVAssetWriter *videoWriter = nil;
    AVAssetWriterInput *writerInput = nil;
#ifdef OCR
    OCR *ocr;
#endif /* OCR */
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"MM-dd-yyyy HH.mm"];
    NSString        *outputPath; 
	
    UInt8 *receiveBuf = NULL;        // Buffer for receiving network datagrams
    UInt32 *winData = NULL;          // Backing store for the window. 
    int pWidth = -1, pHeight = -1;   // Previous width and height to detect and perhaps 
    unsigned int pmaskX = -1, pmaskY = -1, pmaskWidth = -1, pmaskHeight = -1;
    UInt8 *updateData = NULL, *tmpUpdateData = NULL;       // Buffer for receiving updates
	
    // Figure out what window I am supposed to operate on
    int sessionIndex;
    for (sessionIndex = 0; sessionIndex < NUM_SESSIONS; sessionIndex++ ) {
        if (activeNSSessions[sessionIndex] == ns)
            break;
    }
    if (sessionIndex == NUM_SESSIONS) {
        NSLog(@"FATAL: Something is wrong");
        
        return;
    }
    stopSession[sessionIndex] = false;
    int receiveSocket = socket(AF_INET, SOCK_STREAM, 0);
    
    // Try to find the Streamer's network address that is accessible by me
    boolean_t connected = false;
    NSArray *addresses = [ns addresses];
    NSUInteger arrayCount = [addresses count];
    for (unsigned long i = 0; i < arrayCount; i++) {
        NSData *address = [addresses objectAtIndex:i];
        struct sockaddr_in *address_sin = (struct sockaddr_in *)[address bytes];
        
        char buffer[1024];
        NSLog(@"DEBUG: Trying... %s:%d", inet_ntop(AF_INET, &(address_sin->sin_addr), buffer, sizeof(buffer)), ntohs(address_sin->sin_port));
        
        if (address_sin->sin_family == AF_INET) {
            if (connect(receiveSocket, (struct sockaddr *)address_sin, (socklen_t)sizeof(struct sockaddr_in)) == 0) {
                struct timeval tv;
				
                tv.tv_sec  = 300;
                tv.tv_usec = 0;
                setsockopt(receiveSocket, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
                
                connected = true;
                break;
            }
        }
    }
    
    if (connected) {
        dispatch_queue_t dispatchQueue = nil;
        // CGSize size;
        __block AVAssetWriterInputPixelBufferAdaptor *adaptor;
        __block unsigned long updateCount = 0;
        __block bool updated = true;
        __block NSDate *timeStart = nil;
		
        while (stopSession[sessionIndex] != true) {
            ssize_t len;
            UInt32 pktSize;
            
            // First receive the packet size
            if (recv(receiveSocket, &pktSize, sizeof(pktSize), 0) == -1) 
                break;
            
            // Now receive this much data - freeing memory from prior loops
            if (receiveBuf)
                free(receiveBuf);
            receiveBuf = malloc(pktSize);
            
            len = 0;
            while ((UInt32) len < pktSize) {
                ssize_t recvLen = recv(receiveSocket, receiveBuf + len, pktSize - len, 0);
                if (recvLen <= 0) 
                    break;
                len += recvLen;
            }
            if (len != pktSize)
                break;
            
            z_stream strm;
            UInt32 out[5];  // space for the first three integers
            unsigned int width, height, x, y, w, h;
            unsigned int maskX, maskY, maskWidth, maskHeight;
            
            // First, uncompress the first three integers which repreent the width, height, x, y, w and h
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
                case Z_NEED_DICT:
                case Z_DATA_ERROR:
                case Z_MEM_ERROR:
                    (void)inflateEnd(&strm);
                    continue;
            }
            assert(strm.avail_out == 0);
            
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
            
            /*
             if ((x != 0) || (y != 0) || (w != width) || (h != height))
             NSLog(@"It is possible");
             */
            assert(w<=width);
            assert(h<=height);
            
            // If this is the first time, then create a new window to show 
            if (((int) width !=  pWidth) || ((int) height != pHeight)) {
                if (pWidth != -1) {
                    NSLog(@"Dynamically changing window size not support yet %dx%d from %dx%d", width, height, pWidth, pHeight);
                    break;
                } else
                    NSLog(@"Setting window of size %dx%d", width, height);
                pWidth = width;
                pHeight = height;
                // winData = calloc(width * height, sizeof(UInt32));
                updateData = malloc(width * height * sizeof(UInt32));   // Allocate once and reuse
                tmpUpdateData = malloc(width * height * sizeof(UInt32));    // Needed for bitmap encoding
				
                NSDictionary *keys = [NSNetService dictionaryFromTXTRecordData:[ns TXTRecordData]];
                NSData *data = [keys objectForKey:@"name"];
                NSString *name = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
				
                outputPath = [[NSString alloc] initWithFormat:@"Movies/DisplayCast/%@/%@", name, [formatter stringFromDate:[NSDate date]]];
				
                NSString *path = [[NSString alloc] initWithFormat: @"Movies/DisplayCast/%@", name];
                mkdir([[NSHomeDirectory() stringByAppendingPathComponent:@"Movies/DisplayCast"] UTF8String], 0755);
                mkdir([[NSHomeDirectory() stringByAppendingPathComponent:path] UTF8String], 0755);
                // [path release];
				
                timeStart = [NSDate date];
				
                path = [[NSString alloc] initWithFormat: @"%@.mp4", outputPath];
                NSString *betaCompressionDirectory = [NSHomeDirectory() stringByAppendingPathComponent:path];
				
                unlink([betaCompressionDirectory UTF8String]);
                // [formatter release];
                // [path release];
				
                //----initialize compression engine
                NSError *error = nil;
                videoWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:betaCompressionDirectory] fileType:AVFileTypeQuickTimeMovie /* AVFileTypeMPEG4 */  error:&error];
                NSParameterAssert(videoWriter);
                if(error)
                    NSLog(@"error = %@", [error localizedDescription]);
                videoWriter.shouldOptimizeForNetworkUse = YES;
				
                NSDictionary *codecSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                               [NSNumber numberWithInt:5000000], AVVideoAverageBitRateKey,
                                               [NSNumber numberWithInt:100], AVVideoMaxKeyFrameIntervalKey,
                                               nil];
                NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:AVVideoCodecH264, AVVideoCodecKey,
                                               [NSNumber numberWithInt:width], AVVideoWidthKey,
                                               [NSNumber numberWithInt:height], AVVideoHeightKey,
                                               codecSettings, AVVideoCompressionPropertiesKey,
                                               nil];
				
                writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
                writerInput.expectsMediaDataInRealTime = YES;
                
                NSDictionary *sourcePixelBufferAttributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                                                       [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey, nil];
                adaptor = [AVAssetWriterInputPixelBufferAdaptor 
						   assetWriterInputPixelBufferAdaptorWithAssetWriterInput:writerInput
						   sourcePixelBufferAttributes:sourcePixelBufferAttributesDictionary];
                NSParameterAssert(writerInput);
                NSParameterAssert([videoWriter canAddInput:writerInput]);
				
				if (![videoWriter canAddInput:writerInput]) {
					NSLog(@"FATAL: Could not add input");
					return;
				}
					
				[videoWriter addInput:writerInput];

                [videoWriter startWriting];
                [videoWriter startSessionAtSourceTime:kCMTimeZero];
				
                [netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
                
                [self updateKey:videoWriter andNSNetService:ns];
                dispatchQueue = dispatch_queue_create("com.fxpal.displaycast.archiver.encoder", NULL);
                dispatch_queue_t high = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
				
                dispatch_set_target_queue(dispatchQueue, high);
                
                // size = CGSizeMake(width, height);
            }
            
            if (! ((pmaskX == maskX) && (pmaskY == maskY) && (pmaskWidth == maskWidth) && (pmaskHeight == maskHeight)) ) {
                if (winData != NULL)
                    bzero(winData, width * height * sizeof(UInt32));
                
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
                
                switch (inflate(&strm, flush)) {
                    case Z_STREAM_ERROR:
                    case Z_NEED_DICT:
                    case Z_DATA_ERROR:
                    case Z_MEM_ERROR:
                        (void)inflateEnd(&strm);
                        continue;
                }
                uncompressed += strm.avail_out;
                // } while (uncompressed < (w * h * sizeof(UInt32)));
            } while (sz != (int) strm.avail_out);
            
            /* clean up and return */
            (void)inflateEnd(&strm);
            
            // Now perform bitmap encoding's decoding
            int bmStart = 0;
            int srcStart = w*h;
            
			if (tmpUpdateData != NULL)
                for (unsigned int j = 0; j < h; j++) {
                    for (unsigned int i = 0; i < w; i++) {
                        if (tmpUpdateData[bmStart] == 0xFF) {
                            // Blue
                            updateData[bmStart * sizeof(UInt32)] = tmpUpdateData[srcStart++];
                            // Green
                            updateData[bmStart * sizeof(UInt32) + 1] = tmpUpdateData[srcStart++];
							// Red
                            updateData[bmStart * sizeof(UInt32) + 2] = tmpUpdateData[srcStart++];
							// Alpha
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
            
            updateCount++;
            // NSLog(@"Update count is %lu", updateCount);
			
            if (winData == NULL) {
                assert(updateData != NULL);
                assert((w == width) && (h == height));
				assert((width*height) != 0);
                
                winData = malloc(width * height * sizeof(UInt32));
                drawWin(winData, width, height, 0, 0, width, height, (UInt32 *) updateData);
				
#ifdef OCR
                ocr = [[OCR alloc] init];
                [ocr setWidth:width];
                [ocr setHeight:height];
                [ocr setData:winData];
                [ocr setIsDone:FALSE];
                [ocr setOutputPath:outputPath];
                [ocr setTimeStart:timeStart];
				
                [NSThread detachNewThreadSelector:@selector(startOCR:) toTarget:self withObject:ocr];
#endif /* OCR */
                
				
                // [[NSRunLoop mainRunLoop] addTimer:nst forMode:NSRunLoopCommonModes]; 
                // [[NSRunLoop mainRunLoop] addTimer:nst forMode:NSModalPanelRunLoopMode];
                // [nst fire];
				
                // BOOL timerState = [nst isValid];
                // NSLog(@"Timer Validity is: %@", timerState?@"YES":@"NO");
                
                // [self.timer fire];
                // ??? [self performSelector:@selector(performOCR:) withObject:ocr afterDelay:0.1];
				
                [writerInput requestMediaDataWhenReadyOnQueue:dispatchQueue usingBlock:^{
                    // unsigned long processedUpdate = 0;
                    // int prevtm = -1;
					int frame = 0;
                    CVPixelBufferRef buffer = NULL;
                    UInt32 *winDataCopy = malloc(width * height * sizeof(UInt32));
					NSAssert(winDataCopy != NULL, @"Memory allocation failed");
                    
                    while ([writerInput isReadyForMoreMediaData]) {
                        /*
						int tm = ([timeStart timeIntervalSinceNow] * -ARCHIVER_FPS);
                        if (tm == prevtm)	// Too fast, not expecting the next frame right now
                            continue;
                        prevtm = tm;
                        */
                            // Does not support kCVPixelFormatType_32RGBA
							// Does not support kCVPixelFormatType_32ABGR
							// Supports kCVPixelFormatType_32ARGB
							// Supports kCVPixelFormatType_32BGRA

                        if (updated == true) {
                            updated = false;
                            if (CVPixelBufferCreateWithBytes (NULL, width, height, kCVPixelFormatType_32BGRA, winData, width * 4, NULL, NULL, NULL, &buffer) == kCVReturnSuccess) {
                                // processedUpdate = updateCount;
                                
                                // NSLog(@"Time is %d frame is %d and updateCount is %ld", tm, frame, updateCount);
                                if(![adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(([timeStart timeIntervalSinceNow] * -ARCHIVER_FPS), ARCHIVER_FPS)]) {
                                    NSLog(@"FATAL: failed to append pixel buffer");
                                    
                                    break;
                                }
                            }
                            if (buffer != NULL)
                                CFRelease(buffer);
                            buffer = NULL;
                        }
                        frame++;
                        
                        if (stopSession[sessionIndex] == true)
                            break;
                        [NSThread sleepForTimeInterval:(1.0/ARCHIVER_FPS)];
                    }
                    free(winDataCopy);
					
					// NSLog(@"Wrapping up");
					[writerInput markAsFinished];
					
					NSString *myID = [NSString stringWithFormat:@"%lu", [videoWriter hash]];
					[myKeys removeObjectForKey:myID];
					[netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
					
                    if ([videoWriter finishWriting] == NO)
                        NSLog(@"Video completion failed");
                }];
            } else {
                // Overlay the update onto my view of the frame
                drawWin(winData, width, height, x, y, w, h, (UInt32 *) updateData);
                updated = true;
            }
        }
		
        NSString *myID = [[NSString alloc] initWithFormat:@"%lu", [activeNSSessions[sessionIndex] hash]];
        [myKeys removeObjectForKey:myID];
        [netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
		
        activeNSSessions[sessionIndex] = nil;
        [ns stop];
    } else {
        NSLog(@"Window closed");
        activeNSSessions[sessionIndex] = nil;
        [ns stop];
    }
    
#ifdef OCR
    if (ocr != nil) {
        ocr = nil;
    }
#endif /* OCR */
    
    [ns stop];
    
#if 0
    if (writerInput != nil) {
        [writerInput markAsFinished];
		
        NSString *myID = [NSString stringWithFormat:@"%lu", [videoWriter hash]];
        [myKeys removeObjectForKey:myID];
        [netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
		
        // if ([videoWriter finishWriting] == NO)
        //    NSLog(@"Video completion failed");
        // [videoWriter release];
    }
#endif /* 0 */
	
    //  NSLog(@"Okay, wrapping up %d", stopSession[sessionIndex]);
	
    close(receiveSocket);
    if (receiveBuf)
        free(receiveBuf);
    if (winData)
        free(winData);
    if (updateData)
        free(updateData);
    if (tmpUpdateData)
        free(tmpUpdateData);
    
#ifdef OCR
    [ocr setIsDone:TRUE];
#endif /* OCR */
}
@end

@implementation ArchiverAppDelegate (NSApplicationDelegate)
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
#pragma unused(notification)
    for (int indx = 0; indx < NUM_SESSIONS; indx++)
        activeNSSessions[indx] = nil;
	
	if (myUniqueID == nil) {
		GetUniqueID *uid = [[GetUniqueID alloc] init];
        
		myUniqueID = [NSString stringWithFormat:@"archiver-%@", [uid GetHWAddress]];
	}
	
    // Start the Bonjour browser.
    _browser = [[NSNetServiceBrowser alloc] init];
    [_browser setDelegate:self];
    [_browser searchForServicesOfType:STREAMER inDomain:BONJOUR_DOMAIN];
    
    // Fake retain by storing in resolution NSNetServiceBrowser in an array
    _resolvers = [[NSMutableSet alloc] initWithCapacity:10];
    
    // Next, start listening for requests to myself
    int fdForListening = socket(AF_INET6, SOCK_STREAM, 0);
    struct sockaddr_in6 serverAddress6;
    
    memset(&serverAddress6, 0, sizeof(serverAddress6));
    serverAddress6.sin6_family = AF_INET6;
    serverAddress6.sin6_port = 0; // htons(11223);
    serverAddress6.sin6_len = sizeof(serverAddress6);
    bind(fdForListening, (const struct sockaddr *) &serverAddress6, sizeof(serverAddress6));
	
    socklen_t namelen = sizeof(serverAddress6);
    getsockname(fdForListening, (struct sockaddr *) &serverAddress6, &namelen);
    
    listen(fdForListening, 1);
	
    CFSocketContext context = {0, (__bridge void *) self, NULL, NULL, NULL};
    CFRunLoopSourceRef  rls;
    CFSocketRef listeningSocket = CFSocketCreateWithNative(NULL, fdForListening, kCFSocketAcceptCallBack,ListeningSocketCallback, &context);
    if (listeningSocket != NULL) {
        assert( CFSocketGetSocketFlags(listeningSocket) & kCFSocketCloseOnInvalidate );
        fdForListening = -1;        // so that the clean up code doesn't close it
		
        rls = CFSocketCreateRunLoopSource(NULL, listeningSocket, 0);
        assert(rls != NULL);
		
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
        CFRelease(rls);
    }
	
    // Register to listen for preferencepane notifications
	NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(prefcallbackWithNotification:) name:@"Preferences Changed" object:@"com.fxpal.displaycast.Archiver"];
	
    // Register our service with Bonjour.
    unsigned int chosenPort = ntohs(serverAddress6.sin6_port);
    NSString *archiverID = [[NSUserDefaults standardUserDefaults] stringForKey:myUniqueID];
    if (archiverID == nil) {  // Generate a new player ID
        NSLog(@"Generating new unique ID for myself");
        
        CFUUIDRef	uuidObj = CFUUIDCreate(nil);
        archiverID = [(__bridge_transfer NSString*)CFUUIDCreateString(nil, uuidObj) substringToIndex:8];
        [[NSUserDefaults standardUserDefaults] setObject:archiverID forKey:myUniqueID];
        CFRelease(uuidObj);
		
		NSString *str = NSFullUserName();
		
        if (str == nil)
            str = @"Unknown's Archiver";
        else
            str = [NSString stringWithFormat:@"%@'s Archiver", str];
        [[NSUserDefaults standardUserDefaults] setObject:str forKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
    }
    
    netService = [[NSNetService alloc] initWithDomain:BONJOUR_DOMAIN type:ARCHIVER name:archiverID port:chosenPort];
    if (netService != nil) {
        // Deprecated in 10.8
        // SInt32 major, minor, bugfix;
        // Gestalt(gestaltSystemVersionMajor, &major);
        // Gestalt(gestaltSystemVersionMinor, &minor);
        // Gestalt(gestaltSystemVersionBugFix, &bugfix);
        // NSString *systemVersion = [NSString stringWithFormat:@"OSX %d.%d.%d", major, minor, bugfix];
        NSString *systemVersion = [NSString stringWithFormat:@"OSX %@", [[NSProcessInfo processInfo] operatingSystemVersionString]];
        
		NSString *ver = [[NSString alloc] initWithFormat:@"%f", VERSION];
		
        /*
         myKeys = [NSMutableDictionary dictionaryWithObjectsAndKeys:self.serviceName, @"name", [ NSString stringWithFormat:@"0x0x%.0fx%.0f", screenBounds.size.width, screenBounds.size.height], @"screen0", systemVersion, @"osVersion", @"NOTIMPL", @"locationID", [[NSHost currentHost] localizedName], @"machineName", nil];
         */
        myKeys = [[NSMutableDictionary alloc] initWithObjectsAndKeys:self.serviceName, @"name", systemVersion, @"osVersion", @"NOTIMPL", @"locationID", [[NSHost currentHost] localizedName], @"machineName", ver, @"version", nil];
        [netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
        [netService setDelegate:self];
        [netService publishWithOptions:NSNetServiceNoAutoRename /* 0 */];
    }
    close(fdForListening);
}

- (void)applicationWillTerminate:(NSNotification *)notification {
#pragma unused(notification)
}
@end

@implementation ArchiverAppDelegate (NSNetServiceDelegate)
#pragma mark * Bonjour stuff
- (void)netServiceDidPublish:(NSNetService *)sender {
#pragma unused(sender)
    // assert(sender == self.netService);
    // Bonjour might have changed our name, we are not going to save this temporary name [sender name]
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict {
#pragma unused(sender, errorDict)
    // assert(sender == self.netService);
    // NSLog(@"DEBUG: Did not publish - %@, %@", [sender name], errorDict);
    NSLog(@"Duplicate instance. Quietly exitting");
    exit(0);
}
@end

@implementation ArchiverAppDelegate (NSNetServiceBrowserDelegate)
#pragma mark * Browsing
- (void)netService:(NSNetService *)ns didUpdateTXTRecordData:(NSData *)data {
    NSString *nm = [ns name];
	
    // Pick the player listing to update the name
    for (PlayerListing *pl in self.servicesArray.content) {
        NSNetService *plns = [pl ns];
        if ([[plns name] isEqualToString:nm]) {
            NSDictionary *keys = [NSNetService dictionaryFromTXTRecordData:data];
            NSData *dt = [keys objectForKey:@"name"];
            NSString *name = [[NSString alloc] initWithData:dt encoding:NSUTF8StringEncoding];
            
            // [[pl name] release];
            [pl setName:name];
			
            NSLog(@"Updated txt record name to %@", name);
            
            // [dt release];
            // [keys release];
        }
    }
}

/* 
 NSDictionary *myKeys = [NSNetService dictionaryFromTXTRecordData:[ns TXTRecordData]];
 NSData *data = [myKeys objectForKey:@"name"];
 NSString *name = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
 */
- (void)netServiceDidResolveAddress:(NSNetService *)ns {
    NSString *nm = [ns name];
    
    for (PlayerListing *pl in self.servicesArray.content) {
        NSNetService *plns = [pl ns];
        if ([[plns name] isEqualToString:nm]) {
            NSLog(@"Duplicate resolution?");
            [ns stop];
            
            return;
        }
    }
	
    // PlayerListing *pl = [[PlayerListing alloc] initWithName:[ns name] andService:ns];
    PlayerListing *pl = [[PlayerListing alloc] init];
    [pl setNs:ns];
	
    // This name will later be overridden when we get the TXT record update
    [pl setName:@"Resolving name..."];
    
    // NSLog(@"I am setting PlayerListing to %@", [ns name]);
    NSSet *setToAdd = [[NSSet alloc] initWithObjects:pl, nil];
    
    [self willChangeValueForKey:@"services" withSetMutation:NSKeyValueUnionSetMutation usingObjects:setToAdd];
    [self.services addObject:pl];
    [self  didChangeValueForKey:@"services" withSetMutation:NSKeyValueUnionSetMutation usingObjects:setToAdd];
	
    [ns startMonitoring];   // For txt record updates
}

- (void)netService:(NSNetService *)ns didNotResolve:(NSDictionary *)errorDict {
    NSLog(@"Did not resolve %@ because of %@", [ns name], errorDict);
    [_resolvers removeObject:ns];
    
    [ns stop];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
#pragma unused(moreComing)
    
    assert(aNetServiceBrowser == self.browser);
#pragma unused(aNetServiceBrowser)
    
    [_resolvers addObject:aNetService];
    
    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:5.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    assert(aNetServiceBrowser == self.browser);
#pragma unused(aNetServiceBrowser)
    [_resolvers removeObject:aNetServiceBrowser];
    
    NSString *nm = [aNetService name];
    assert(nm != nil);
    
    NSNetService *ns = nil;
    // NSString *nsm;
    
    // PlayerListing *pl = nil;
    for (PlayerListing *p in self.servicesArray.content) {
        ns = [p ns];
        // nsm = [[NSString alloc] initWithString:[ns name]];
        // NSLog(@"WTF: %@ vs %@", nsm, nm);
        if ([[ns name] isEqualToString:nm]) {
            [self.pendingServicesToRemove addObject:p];
            // pl = p;
            
            break;
        }
    }
    
    [aNetService stop];
    
    if (ns != nil) {
        // If this session was active, remove and close the window
        for (int indx = 0; indx < NUM_SESSIONS; indx++ ) {
            if (activeNSSessions[indx] == ns) {
                [activeNSSessions[indx] stop];
                
                activeNSSessions[indx] = nil;
            }
        }
    }
    
    if ( ! moreComing ) {
        NSSet *setToRemove;
		
        setToRemove = [self.pendingServicesToRemove copy];
        assert(setToRemove != nil);
        [self.pendingServicesToRemove removeAllObjects];
		
        [self willChangeValueForKey:@"services" withSetMutation:NSKeyValueMinusSetMutation usingObjects:setToRemove];
        [self.services minusSet:setToRemove];
        [self  didChangeValueForKey:@"services" withSetMutation:NSKeyValueMinusSetMutation usingObjects:setToRemove];
    }
}

- (void)stopBrowsingWithStatus:(NSString *)status {
#pragma unused(status)
    assert(status != nil);
    
    [self.browser setDelegate:nil];
    [self.browser stop];
    self.browser = nil;
    
    [self.pendingServicesToAdd removeAllObjects];
    [self.pendingServicesToRemove removeAllObjects];
    
    [self willChangeValueForKey:@"services"];
    [self.services removeAllObjects];
    [self  didChangeValueForKey:@"services"];
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser {
    assert(aNetServiceBrowser == self.browser);
#pragma unused(aNetServiceBrowser)
    [self stopBrowsingWithStatus:@"Service browsing stopped."];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict {
    assert(aNetServiceBrowser == self.browser);
#pragma unused(aNetServiceBrowser)
    assert(errorDict != nil);
#pragma unused(errorDict)
    [self stopBrowsingWithStatus:@"Service browsing failed."];
}
@end

// Crud left over, might be useful for something?
#if 0
- (CVPixelBufferRef )pixelBufferFromCGImage:(CGImageRef)image size:(CGSize)size {
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey, 
							 [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey, nil];
	CVPixelBufferRef pxbuffer = NULL;
	CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options, &pxbuffer);
    // CVReturn status = CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pxbuffer);
	
	NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL); 
	
	CVPixelBufferLockBaseAddress(pxbuffer, 0);
	void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
	NSParameterAssert(pxdata != NULL);
	
	CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(pxdata, size.width, size.height, 8, 4*size.width, rgbColorSpace, kCGImageAlphaPremultipliedFirst);
	NSParameterAssert(context);
	
	CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
	
	CGColorSpaceRelease(rgbColorSpace);
	CGContextRelease(context);
	
	CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
	
	return pxbuffer;
}

// displayWin(player, width, height, winData);			
//			void displayWin(NSImageView *player, int width, int height, UInt32 *buf) {
CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
CGDataProviderRef bitmapData = CGDataProviderCreateWithData(NULL, winData, width * height * sizeof(UInt32), NULL /*releaseProvider*/);
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
NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:myImage];
NSImage *image = [[[NSImage alloc] init] autorelease];
[image addRepresentation:bitmapRep];

CVPixelBufferRef buffer = (CVPixelBufferRef)[self pixelBufferFromCGImage:image size:size];
if (buffer) {
	if(![adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(++frame, 20)])
		NSLog(@"FAIL");
        else
            NSLog(@"Success:%d", frame);
            CFRelease(buffer);
            }

if(frame >= 120) {
	[writerInput markAsFinished];
	[videoWriter finishWriting];
	[videoWriter release];
	break;
}

[bitmapRep release];

CGImageRelease(myImage);
CGDataProviderRelease(bitmapData);
CGColorSpaceRelease(colorSpace);
/*
 [writerInput requestMediaDataWhenReadyOnQueue:dispatchQueue usingBlock:^{
 while ([writerInput isReadyForMoreMediaData]) {
 if(++frame >= 120) {
 [writerInput markAsFinished];
 [videoWriter finishWriting];
 [videoWriter release];
 break;
 }
 
 CVPixelBufferRef buffer = (CVPixelBufferRef)[self pixelBufferFromCGImage:theImage size:size];
 if (buffer) {
 if(![adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(frame, 20)])
 NSLog(@"FAIL");
 else
 NSLog(@"Success:%d", frame);
 CFRelease(buffer);
 }
 }
 }];
 */
#endif /* 0 */


#if 0
- (void)windowStateChanged:(NSNotification *)notification {
	[self windowStateChanged:notification];
	/*
     NSWindow *window = [notification object];
     
     for (int sessionIndex = 0; sessionIndex < NUM_SESSIONS; sessionIndex++ ) {
     if (windows[sessionIndex] == window) {
     [self updateKey:window andNSNetService:activeNSSessions[sessionIndex]];
     break;
     }
     }
	 */
}

- (void)windowDidResize:(NSNotification *)notification {
    [self windowStateChanged:notification];
}

- (void)windowDidMove:(NSNotification *)notification {
    [self windowStateChanged:notification];
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
    [self windowStateChanged:notification];
}
- (void)windowDidDeminiaturize:(NSNotification *)notification {
    [self windowStateChanged:notification];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    [self windowStateChanged:notification];
}
- (void)windowDidExitFullScreen:(NSNotification *)notification {
    [self windowStateChanged:notification];
}

- (void)windowWillClose:(NSNotification *)notification {
#if 0
	NSWindow *window = [notification object];
	
    for (int sessionIndex = 0; sessionIndex < NUM_SESSIONS; sessionIndex++ ) {
        if (windows[sessionIndex] == window) {
            stopSession[sessionIndex] = true;
            [window orderOut:self];
            activeNSSessions[sessionIndex] = nil;
            
            NSString *myID = [[[NSString alloc] initWithFormat:@"%lu", [window hash]] autorelease];
            [myKeys removeObjectForKey:myID];
            [netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
            break;
        }
    }
#endif /* 0 */
}
#endif /* 0 */

