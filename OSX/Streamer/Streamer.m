	// Copyright (c) 2012, Fuji Xerox Co., Ltd.
	// All rights reserved.
	// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "Streamer.h"
#import "Globals.h"

#ifdef USE_BLUETOOTH
#import <IOBluetooth/IOBluetooth.h>
#import <IOBluetooth/IOBluetoothUserLib.h>
#import <IOBluetooth/IOBluetoothUtilities.h>
#import <IOBluetooth/objc/IOBluetoothDeviceInquiry.h>
#import <IOBluetooth/objc/IOBluetoothDevice.h>
#import <IOBluetooth/objc/IOBluetoothHostController.h>
#endif /* USE_BLUETOOTH */

#include <sys/socket.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <zlib.h>

@interface Streamer () <NSNetServiceDelegate>
@property (nonatomic, copy,   readwrite) NSString *serviceName;
@property (nonatomic, copy,   readonly ) NSString *defaultServiceName;
@property (nonatomic, retain, readwrite) NSNetService *netService;
@end

@implementation Streamer

@synthesize streamerID = _streamerID;
@synthesize faunus;

NSMutableDictionary *myKeys = nil;  // To be broadcast via Bonjour

size_t	width, height;   // Our screen dimensions
CGRect	maskRect;        // Server size masking
bool	maskValid = FALSE;
UInt32  *prevFramebufferData = NULL;  // Previous framebuffer

NSMutableArray	*activePlayers;
int maxPacketSize;

	// Prototypes
static void maskListeningSocketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

	// Takes sz bytes from src, Zlib compresses them. Zlib compress will use UDP packet size for a chunk. Each chunk is sent to streamSocket. The packet format for each chunk is <seqno:16>:<cnt:8>:<pktcnt:8><chunk data>. Seqno is monotonically increasing. pktcount is the maximum number of chunks and cnt is the count of this chunk (among the pktcount chunks) 

	// Currently, we send the same object to n clients sequentially. This works in corporate setting where all clients experience the same network. Should be parallelized so that each client can run at its own pace. Ideally, some clients must be able to fall behind (and not receive some window updates) but that would require keeping track of per client state
int compressSend(unsigned char *src, unsigned int sz) {
		// Store each chunk from deflate routine so as to send them as a separate packet
    unsigned char *out[PENDING_UPDATES];
    unsigned int outsz[PENDING_UPDATES], pktCount = 0;
    UInt32 compSize = 0;
    z_stream strm;
	
    /* allocate deflate state */
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    if (deflateInit(&strm, STREAMER_ZLIB_COMPRESSION) != Z_OK)
        exit(1);
    
    strm.avail_in = sz;
    strm.next_in = src;
    do {
        int flush = Z_FINISH; // Z_SYNC_FLUSH;
        out[pktCount] = (unsigned char *) malloc (maxPacketSize);
        strm.next_out = out[pktCount];
        strm.avail_out = maxPacketSize;
        
        if (deflate(&strm, flush) == Z_STREAM_ERROR)
            exit(1);
        outsz[pktCount] = (maxPacketSize - strm.avail_out);
        compSize += outsz[pktCount];
        
        assert(pktCount < PENDING_UPDATES);
        pktCount++;
    } while (strm.avail_out == 0);
    (void)deflateEnd(&strm);
	
	NSMutableArray *toRemove = [[NSMutableArray alloc] init];
	for (unsigned int cnt=0; cnt < pktCount; cnt++) {
		for (NSNumber *nsock in activePlayers) {
			if (cnt == 0)	// Send the header
				if (send([nsock intValue], &compSize, sizeof(UInt32), 0) == -1) {
					[toRemove addObject:nsock];
					
					continue;
				}
			
			ssize_t sent = 0, curSent;
			while (sent < outsz[cnt]) {
				if ((curSent = send([nsock intValue], (out[cnt] + sent), (outsz[cnt]-sent), 0)) == -1) {
					switch(errno) {
						case EMSGSIZE:
							printf("Packet size error: %d\n", outsz[cnt]);
							break;

						case ENOBUFS:
							printf("tcp send: No buffers available\n");
							break;

						default:
							NSLog(@"tcp send: Error is; %d", errno);
							
							perror("tcpSend");
							[toRemove removeObject:nsock];		// We search through the entire array.
																// Maybe search and delete the first entry should be enough
							[toRemove addObject:nsock];
							break;
					}
				} else
					sent += curSent;
			}
		}
		if ([toRemove count] != 0)
			[activePlayers removeObjectsInArray:toRemove];
		
		free(out[cnt]);
		outsz[cnt] = -1;
	}
	[toRemove release];
	
    return compSize;
}

void sendInitialIframe() {
	UInt32 inc = (UInt32) height;						// If we don't want to send the entire screen in one shot, specify the height fraction to send
	UInt32 x = 0, w = (UInt32) width, h = inc;
    UInt32 sz = w * h * sizeof(UInt32);
    UInt32 *sendBuf = (UInt32 *)calloc (sz + 5*sizeof(UInt32), 1);
    
		// Acquire fresh new values for the display contents
    CGImageRef pimageRef = CGDisplayCreateImage(CGMainDisplayID());
    CGDataProviderRef pimageDataRef = CGImageGetDataProvider(pimageRef);
    CFDataRef pColorData = CGDataProviderCopyData(pimageDataRef);
    CFRange range = CFRangeMake(0,CFDataGetLength(pColorData));
    
    if (prevFramebufferData != NULL)
        free(prevFramebufferData);
    prevFramebufferData = malloc(range.length);
    CFDataGetBytes(pColorData, range , (UInt8 *) prevFramebufferData);
    CFRelease(pColorData);
    CGImageRelease(pimageRef);
    
    for (UInt32 y = 0; y < height; y += inc) {
        int n = 0;
        
        if ((y+h) > height) {
            h = (UInt32) height - y;
            sz = w * h * sizeof(UInt32);
        }
        *(sendBuf + n++) = (UInt32) htonl((width << 16) + (height & 0xffff));
		*(sendBuf + n++) = (UInt32) htonl(((int) maskRect.origin.x << 16) + ((int) maskRect.origin.y & 0xffff));
		*(sendBuf + n++) = (UInt32) htonl(((int) maskRect.size.width << 16) + ((int) maskRect.size.height & 0xffff));
        *(sendBuf + n++) = (UInt32) htonl((x << 16) + (y & 0xffff));
        *(sendBuf + n++) = (UInt32) htonl ((w << 16) + (h & 0xffff));
		
        UInt8 *dataBuf = (UInt8 *)sendBuf;
        
        dataBuf += (5 * sizeof(UInt32));
        memset(dataBuf, 0xFF, w * h);		// bitmap is 1 for all pixels
        dataBuf += (w * h);
        
        for (unsigned int iy = 0; iy < h; iy++) {
            for (unsigned int ix = 0; ix < w; ix++) {
                int indx = ((int) width * (y + iy)) + (x + ix);
                UInt32 cur = *(prevFramebufferData + indx);
				
                *dataBuf++ = (UInt8) (cur & 0xFF);
                *dataBuf++  = (UInt8) (cur >> 8 ) & 0xFF;
                *dataBuf++  = (UInt8) (cur >> 16) & 0xFF;
            }
        }
        
        compressSend((UInt8 *)sendBuf, sz + (5 * sizeof(UInt32)));
    }
    free(sendBuf);
} // sendInitialIframe

	// Each rectangle is sent as follows: <width:16><height:16><maskX:16><maskY:16><maskWidth:16><maskHeight:16><x:16><y:16><width:16><height:16>
void MyScreenRefreshCallback (CGRectCount count, const CGRect *rectArray, void *userParameter) {
#pragma unused(userParameter)

	if ([activePlayers count] == 0)
		return;

	@autoreleasepool {
		boolean_t done = FALSE;
        
			// One could use CGDisplayCreateImageForRect to capture just the screen regions that were changed
		CGImageRef myImageRef = CGDisplayCreateImage(CGMainDisplayID());
		CFDataRef cColorData = CGDataProviderCopyData(CGImageGetDataProvider(myImageRef));
		UInt32 *curFramebufferData = (UInt32 *) CFDataGetBytePtr(cColorData);
		
		for (unsigned int ind = 0; ind < count; ind++) {
			int same = 0, diff = 0, n = 0;
			UInt32 x, y, w, h;
			
			if (maskValid) {
				CGRect intersection = CGRectIntersection(maskRect, rectArray[ind]);
				
				if (CGRectIsNull(intersection))
					continue;						// Drop updates that will be fully masked off
				
				x=(UInt32) intersection.origin.x;
				y=(UInt32) intersection.origin.y;
				w=(UInt32) intersection.size.width;
				h=(UInt32) intersection.size.height;
			} else {
				x = rectArray[ind].origin.x;
				y = rectArray[ind].origin.y;
				w = rectArray[ind].size.width;
				h = rectArray[ind].size.height;
			}

			if ((y+h) > height) {
				continue;

					// WTF. Noticed this in 10.8 (Mountain Lion). I guess these screen capture functions are deprecated. Even CGDisplayCreateImageForRect returns null
					// CGImageRef *img = CGDisplayCreateImageForRect(CGMainDisplayID, rectArray[ind]);
					//				assert(img != nil);
			}


			UInt32 *transformStr = (UInt32 *)malloc((w * h + 5) * sizeof(UInt32));
			UInt8 *bmPtr = (UInt8 *)transformStr + (5 * sizeof(UInt32)), *dataPtr = bmPtr + (w * h);
			int bufSz = w * h + (5 * sizeof(UInt32));
			
			*(transformStr + n++) = (UInt32) htonl((width << 16) + (height & 0xffff));
			*(transformStr + n++) = (UInt32) htonl(((int) maskRect.origin.x << 16) + ((int) maskRect.origin.y & 0xffff));
			*(transformStr + n++) = (UInt32) htonl(((int) maskRect.size.width << 16) + ((int) maskRect.size.height & 0xffff));
			*(transformStr + n++) = (UInt32) htonl((x << 16) + (y & 0xffff));
			*(transformStr + n++) = (UInt32) htonl((w << 16) + (h & 0xffff));
			
			for (unsigned int iy = 0; iy < h; iy++) {
				for (unsigned int ix = 0; ix < w; ix++) {
					int indx = ((int) width * (y + iy)) + (x + ix);

					UInt32 prev = *(prevFramebufferData + indx);
					UInt32 cur = *(curFramebufferData + indx);
					
					if (prev == cur) {
						*bmPtr++ = 0x00;
						
						same++;
					} else {
						*bmPtr++ = 0xFF;
						
						*dataPtr++ = (UInt8) (cur & 0xFF);
						*dataPtr++ = (UInt8) (cur >> 8 ) & 0xFF;
						*dataPtr++ = (UInt8) (cur >> 16) & 0xFF;
						bufSz += 3;
						
						*(prevFramebufferData + indx) = cur; // *(curFramebufferData + indx);
						diff++;
					}
				}
			}
			if (diff) {
					// NSLog(@"Sending: %dx%d %dx%d", x, y, w, h);
				if (compressSend((UInt8 *)transformStr, bufSz) == -1)
					done = TRUE;
			}
			free(transformStr);
			
			if (done == TRUE)
				exit(1);
		}
		
		CFRelease(cColorData);
		CGImageRelease(myImageRef);
	}
}

#pragma mark -
#pragma mark *Preferences
- (void) prefcallbackWithNotification:(NSNotification *)myNotification {
#pragma unused(myNotification)
	[[NSUserDefaults standardUserDefaults] synchronize];
	NSString *myName = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
	if ((myName != nil) && (![myName isEqualToString:self.serviceName])) {
		[myKeys removeObjectForKey:@"name"];
		[myKeys setObject:myName forKey:@"name"];
		
		[self.netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
		[self.netService publishWithOptions:NSNetServiceNoAutoRename];
	}
}

#ifdef STREAMER_ADVERTISE_EXTERNAL_IP
void GetPrimaryIp(char* buffer, socklen_t buflen) {
    assert(buflen >= 16);
    
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    assert(sock != -1);
    
    const char* kGoogleDnsIp = "8.8.8.8";
    uint16_t kDnsPort = 53;
    struct sockaddr_in serv;
    memset(&serv, 0, sizeof(serv));
    serv.sin_family = AF_INET;
    serv.sin_addr.s_addr = inet_addr(kGoogleDnsIp);
    serv.sin_port = htons(kDnsPort);
    
    int err = connect(sock, (struct sockaddr *) &serv, sizeof(serv));
    assert(err != -1);
    
    struct sockaddr_in name;
    socklen_t namelen = sizeof(name);
    err = getsockname(sock, (struct sockaddr *) &name, &namelen);
    assert(err != -1);
    
    const char* p = inet_ntop(AF_INET, &name.sin_addr, buffer, buflen);
    assert(p);
    
    close(sock);
}
#endif /* STREAMER_ADVERTISE_EXTERNAL_IP */

- (id)init {
    self = [super init];
    
    if (self) {
		faunus = [[Faunus alloc] init];		// Create a faunus service instance

        width = CGDisplayPixelsWide(CGMainDisplayID());
        height = CGDisplayPixelsHigh(CGMainDisplayID());

		activePlayers = [[NSMutableArray alloc] init];

        maskRect = CGRectMake(0.0, 0.0, width, height);
        maskValid = false;
		in_port_t maskPort = [self createServerSocketWithAcceptCallBack:maskListeningSocketCallback];
		in_port_t myPort = [self createServerSocketWithAcceptCallBack:streamListeningSocketCallback];
		
			// HTTP server to respond to SNAPSHOT requests
		HTTPServer *server = [[HTTPServer alloc] init];
		[server setPort:9765];
		
		NSError *startError = nil;
		if ([server start:&startError])
			[server setDelegate:self];
		else {
			NSLog(@"Error starting HTTP server for SNAPSHOT service: %@", startError);
			[server dealloc];
			server = nil;
		}
		
		if (myUniqueID == nil) {
			GetUniqueID *uniqid = [[GetUniqueID alloc] init];

			myUniqueID = [[NSString stringWithFormat:@"streamer-%@", [uniqid GetHWAddress]] retain];
			[uniqid release];
		}

		self.streamerID = [[NSUserDefaults standardUserDefaults] objectForKey:myUniqueID];

		if (self.streamerID == nil) {	// First time
			self.streamerID = [faunus createName:STREAMER publicP:YES];	// Try Faunus

				// Faunus was successful
			if (self.streamerID != nil) {
				[[NSUserDefaults standardUserDefaults] setObject:self.streamerID forKey:myUniqueID];
				[[NSUserDefaults standardUserDefaults] synchronize];
			} else {	// Create a temporary ID - will be replaced the next time we contact Faunus service
				CFUUIDRef	uuidObj = CFUUIDCreate(nil);
				CFStringRef uidStr = CFUUIDCreateString(nil, uuidObj);
				[[NSUserDefaults standardUserDefaults] setObject:(id)uidStr forKey:myUniqueID];
				CFRelease(uidStr);
				CFRelease(uuidObj);

				self.streamerID = [[NSUserDefaults standardUserDefaults] objectForKey:myUniqueID];
			}

			NSString *nm = NSFullUserName();
			NSString *str;
			if (nm == nil)
				str = @" Streamer";
			else
				str = [NSString stringWithFormat:@"%@'s Streamer", nm];
			[[NSUserDefaults standardUserDefaults] setObject:str forKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
		} else {
				// Now see if faunus knows about this name. If not, it was created locally and so try to create a faunus name
			BOOL known = NO;
			NSMutableArray *names = [faunus browseLocal:STREAMER];

			for (NSString *name in names) {
				if ([name isEqualToString:self.streamerID]) {
					known = YES;

					break;
				}
			}

			if (known == NO) {
				self.streamerID = [faunus createName:STREAMER publicP:YES];

					// Faunus was successful
				if (self.streamerID != nil) {
					[[NSUserDefaults standardUserDefaults] setObject:self.streamerID forKey:myUniqueID];
					[[NSUserDefaults standardUserDefaults] synchronize];
				}
					// The -Name component is reused
			}
		}
		assert(self.streamerID != nil);		// Will fail when Faunus is completely unavailable

			// NSString *myAddr = [[[NSString alloc] initWithCString:ma encoding:NSASCIIStringEncoding] autorelease];
			// NSLog(@"Address: %@:%d. MaxPacketSize: %d Name: %@\n", myAddr, myPort, maxPacketSize, self.serviceName);
        self.netService = [[[NSNetService alloc] initWithDomain:BONJOUR_DOMAIN type:STREAMER name:self.streamerID port:myPort] autorelease];
        if (self.netService != nil) {
				// Deprecated in 10.8
				// SInt32 major, minor, bugfix;
				// Gestalt(gestaltSystemVersionMajor, &major);
				// Gestalt(gestaltSystemVersionMinor, &minor);
				// Gestalt(gestaltSystemVersionBugFix, &bugfix);
				// NSString *systemVersion = [NSString stringWithFormat:@"OSX %d.%d.%d", major, minor, bugfix];
            NSString *systemVersion = [NSString stringWithFormat:@"OSX %@", [[NSProcessInfo processInfo] operatingSystemVersionString]];
			NSString *screenDimension = [NSString stringWithFormat:@"0x0 %.0zux%.0zu", width, height];
            NSString *ver = [[[NSString alloc] initWithFormat:@"%f", VERSION] autorelease];
            NSString *bluetoothID =	@"NotSupported";

			myKeys = [[NSMutableDictionary dictionaryWithObjectsAndKeys:self.serviceName, @"name", ver, @"version", [[NSHost currentHost] localizedName], @"machineName", systemVersion, @"osVersion", @"NOTIMPL", @"locationID", [NSString stringWithFormat:@"%u", maskPort], @"maskPort", screenDimension, @"screen", NSUserName(), @"userid", bluetoothID, @"bluetooth", @"UNKNOWN", @"nearby", nil] retain];
			if (server != nil)
				[myKeys setValue:[NSString stringWithFormat:@"%u", [server port]] forKey:@"imagePort"];
			
#ifdef STREAMER_ADVERTISE_EXTERNAL_IP
			char ma[64];
			GetPrimaryIp(ma, 64);
			[myKeys setValue:[NSString stringWithCString:ma encoding:NSASCIIStringEncoding] forKey:@"externalIP"];
#endif /* STREAMER_ADVERTISE_EXTERNAL_IP */

            [self.netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
            [self.netService setDelegate:self];
            [self.netService publishWithOptions:NSNetServiceNoAutoRename];

			if ([faunus addAttrs:myKeys forName:self.streamerID] == NO)
				NSLog(@"FATAL: Faunus registration of attributes failed");
			
#ifdef USE_BLUETOOTH
				// This code used to work synchronously and then it was deprecated in 10.6 and now it just hangs when I compile in Lion+. Apple developer forum has no answer on why this fails!!
				// [[IOBluetoothHostController defaultController] addressAsString];
			[self performSelectorInBackground:@selector(getBluetoothDeviceAddress) withObject:nil];
#endif /* USE_BLUETOOTH */
        } else {
            printf("FATAL: Bonjour registration failed\n");
            exit(1);
        }
		
			// Register to listen for preferencepane notifications
		NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(prefcallbackWithNotification:) name:@"Preferences Changed" object:@"com.fxpal.displaycast.Streamer"];
    }
    return self;
}

#ifdef USE_BLUETOOTH
- (void) getBluetoothDeviceAddress {
	NSString *bta = [[IOBluetoothHostController defaultController] addressAsString];
	
    [myKeys removeObjectForKey:@"bluetooth"];
    [myKeys setValue:bta forKey:@"bluetooth"];
    
    [self.netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];

	[faunus addAttrs:myKeys forName:self.streamerID];
}
#endif /* USE_BLUETOOTH */

#pragma mark -
#pragma mark *Locate nearby players using bluetooth
#ifdef USE_BLUETOOTH
- (void) nearbyDevices:(NSString *)names {
	if (self.netService != nil) {
		[myKeys removeObjectForKey:@"nearby"];
		[myKeys setObject:names forKey:@"nearby"];
			// [names retain];
        
		[self.netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
		[self.netService publishWithOptions:NSNetServiceNoAutoRename];

		[faunus addAttrs:myKeys forName:self.streamerID];
	}
}
#endif /* USE_BLUETOOTH */

#pragma mark -
#pragma mark *accept masks
- (void) broadcastMask:(CGRect) mask {
	[myKeys removeObjectForKey:@"maskScreen"];
	NSString *maskVal = (maskValid) ? [NSString stringWithFormat:@"%.0fx%.0f %.0fx%.0f", mask.origin.x, mask.origin.y, mask.size.width, mask.size.height] : @"0x0 0x0";
	[myKeys setObject:maskVal forKey:@"maskScreen"];
		// [maskVal retain];
	
	[self.netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:myKeys]];
	[self.netService publishWithOptions:NSNetServiceNoAutoRename];

	[faunus addAttrs:myKeys forName:self.streamerID];
}

	// Implements the MASK HTTP server
void receiveCmdData(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
#pragma unused(info,type)
    NSString *result;
    
    NSString *command = [[[NSString alloc] initWithData:(NSData *)data encoding:NSUTF8StringEncoding /* NSASCIIStringEncoding */] autorelease];
    NSArray *array = [command componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if (([array count] >= 5) && ([[array objectAtIndex:0] isEqualToString:@"MASK"])) {
		maskRect.origin.x = [[array objectAtIndex:1] intValue];
		maskRect.origin.y = [[array objectAtIndex:2] intValue];
		maskRect.size.width = [[array objectAtIndex:3] intValue];
		maskRect.size.height = [[array objectAtIndex:4] intValue];
		maskValid = !CGRectEqualToRect(maskRect, CGRectMake(0.0, 0.0, width, height));
        
		result = (maskValid) ? [NSString stringWithFormat:@"Mask set to %.0fx%.0f %.0fx%.0f", maskRect.origin.x, maskRect.origin.y, maskRect.size.width, maskRect.size.height] : @"MASK reset";
        
        Streamer *localObjC = [Streamer alloc];
		[localObjC broadcastMask:maskRect];
        [localObjC release];
	} else
		result = @"SYNTAX ERROR";
	
	CFSocketSendData(s, address, (CFDataRef)[result dataUsingEncoding:NSASCIIStringEncoding], 1.0);
	
    CFSocketInvalidate(s);
    CFRelease(s);
}

static void maskListeningSocketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
#pragma unused(type,address,s) 
	
    CFSocketNativeHandle csock = *(CFSocketNativeHandle *)data;
    CFSocketContext CTX = { 0, info, NULL, NULL, NULL };
	
    CFSocketRef sn = CFSocketCreateWithNative(NULL, csock, kCFSocketDataCallBack, receiveCmdData, &CTX);
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, sn, 0);
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    
    CFRelease(source);
    CFRelease(sn);
}

static void streamListeningSocketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
#pragma unused(type,address,s,info) 
    
    CFSocketNativeHandle csock = *(CFSocketNativeHandle *)data;
	
	int set = 1;
	setsockopt(csock, SOL_SOCKET, SO_NOSIGPIPE, (void *)&set, sizeof(int));
	
	struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 10;
    setsockopt (csock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));

    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    setsockopt (csock, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout, sizeof(timeout));
	
	[activePlayers addObject:[NSNumber numberWithInt:csock]];
	
	sendInitialIframe();
}

- (in_port_t)createServerSocketWithAcceptCallBack:(CFSocketCallBack)callback {
	int fdForListening = socket(AF_INET6, SOCK_STREAM, 0);
	
	struct sockaddr_in6 serverAddress6;
	memset(&serverAddress6, 0, sizeof(serverAddress6));
	serverAddress6.sin6_family = AF_INET6;
	serverAddress6.sin6_port = 0;
	serverAddress6.sin6_len = sizeof(serverAddress6);
	bind(fdForListening, (const struct sockaddr *) &serverAddress6, sizeof(serverAddress6));
	
	socklen_t len = sizeof(maxPacketSize);
	maxPacketSize = 64000 + sizeof(UInt32);
	setsockopt(fdForListening, SOL_SOCKET, SO_SNDBUF, (int *)&maxPacketSize, len);
	getsockopt(fdForListening, SOL_SOCKET, SO_SNDBUF, (int *)&maxPacketSize, &len);
	maxPacketSize -= sizeof(UInt32);
	
	listen(fdForListening, 1);
	
	CFSocketContext context = {0, self, NULL, NULL, NULL};
	CFRunLoopSourceRef  rls;
	CFSocketRef listeningSocket = CFSocketCreateWithNative(NULL, fdForListening, kCFSocketAcceptCallBack, callback, &context);
	if (listeningSocket == NULL) {
		return -1;
	} else {
		assert( CFSocketGetSocketFlags(listeningSocket) & kCFSocketCloseOnInvalidate );
		
		rls = CFSocketCreateRunLoopSource(NULL, listeningSocket, 0);
		assert(rls != NULL);
		
		CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
		CFRelease(rls);
		CFRelease(listeningSocket);
	} 
	
	socklen_t namelen = sizeof(serverAddress6);
	getsockname(fdForListening, (struct sockaddr *) &serverAddress6, &namelen);
	
	return ntohs(serverAddress6.sin6_port);
}

#pragma mark -
#pragma mark * Core networking code
@synthesize netService = _netService;

	// An NSNetService delegate callback that's called when the service is successfully 
	// registered on the network.  We set our service name to the name of the service 
	// because the service might be been automatically renamed by Bonjour to avoid 
	// conflicts.
- (void)netServiceDidPublish:(NSNetService *)sender {
    assert(sender == self.netService);
		// self.serviceName = [sender name];
}

	// An NSNetService delegate callback that's called when the service fails to 
	// register on the network.  We respond by shutting down our entire network 
	// service.
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict {
    assert(sender == self.netService);
#pragma unused(sender)
#pragma unused(errorDict)
	switch ((NSInteger)[errorDict objectForKey:NSNetServicesErrorCode]) {
		case NSNetServicesCollisionError: {
			NSLog(@"Duplicate instance. Quietly exitting: %@", errorDict);
			exit(0);
		}

		default: {
			NSLog(@"Could not publish: error: %@ service: %@", errorDict, sender);
		}
	}
}

	// An NSNetService delegate callback that's called when the service spontaneously
	// stops.  This rarely happens on Mac OS X but, regardless, we respond by shutting 
	// down our entire network service.
- (void)netServiceDidStop:(NSNetService *)sender {
    assert(sender == self.netService);
#pragma unused(sender)
		// [self stopWithStatus:@"Network service stopped."];
}

- (NSString *)defaultServiceName {
    NSString *  result;
    
		// [[NSUserDefaults standardUserDefaults] addSuiteNamed:@"com.fxpal.displaycast.Streamer"];
		// NSLog(@"My UID is: %@", myUniqueID);
	result = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
    if (result == nil) {
        NSString *  str;
        
        str = NSFullUserName();
        if (str == nil) {
            result = @" Streamer";
            assert(result != nil);
        } else {
            result = [NSString stringWithFormat:@"%@'s Streamer", str];
            assert(result != nil);
        }
        [[NSUserDefaults standardUserDefaults] setObject:result forKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
    }
    assert(result != nil);
    return result;
}

- (NSString *)serviceName {
    if (self->_serviceName == nil) {
        self->_serviceName = [[self defaultServiceName] copy];
        assert(self->_serviceName != nil);
    }
    return self->_serviceName;
}

- (void)setServiceName:(NSString *)newValue {
    if (newValue != self->_serviceName) {
		[self->_serviceName release];
        self->_serviceName = [newValue copy];
        
        if (self->_serviceName == nil) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
        } else {
            [[NSUserDefaults standardUserDefaults] setObject:self->_serviceName forKey:[NSString stringWithFormat:@"%@-Name", myUniqueID]];
        }
    }
}
@end
