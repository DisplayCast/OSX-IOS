// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

#import "Globals.h"
#import "HTTPServer.h"
#import "GetUniqueID.h"

#ifdef USE_BLUETOOTH
#import <IOBluetooth/IOBluetooth.h>
#import <IOBluetooth/objc/IOBluetoothDeviceInquiry.h>
#endif /* USE_BLUETOOTH */

#define PENDING_UPDATES 1000    // Buffer this many updates

@interface Streamer : NSObject <NSNetServiceBrowserDelegate> {
    NSNetService *      _netService;
    NSString *          _serviceName;
	
	NSString *myUniqueID;
	NSString *_streamerID;
}

@property (nonatomic, retain, readwrite) NSString *streamerID;

#ifdef USE_BLUETOOTH
- (void) nearbyDevices:(NSString *)names;
#endif /* USE_BLUETOOTH */

extern CGRect maskRect;     // Support server size masking

extern void MyScreenRefreshCallback (CGRectCount count, const CGRect *rectArray, void *userParameter);
@end
