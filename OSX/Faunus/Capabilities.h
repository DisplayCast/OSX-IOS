// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>

@interface Capabilities : NSObject {
	NSString *nm;
	NSString *key;
	NSString *operation;
	NSString *capability;
}

@property (nonatomic, retain) NSString *nm;
@property (nonatomic, retain) NSString *key;
@property (nonatomic, retain) NSString *operation;
@property (nonatomic, retain) NSString *capability;

@end
