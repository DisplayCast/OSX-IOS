// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>
#import "redisAttribute.h"
#import "redisCapability.h"

@interface redisName : NSObject
@property (nonatomic, retain) NSString *id;
@property (nonatomic, retain) NSMutableArray *attributes;
@property (nonatomic, retain) NSMutableArray *children;

@property (nonatomic, retain) NSMutableArray *readCapability;
@property (nonatomic, retain) NSMutableArray *writeCapability;

- (NSDictionary *) copyToDictionary;
@end