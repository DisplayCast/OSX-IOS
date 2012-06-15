// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>

@interface redisCapability : NSObject
@property (nonatomic, retain) NSNumber *capabilityToken;
@property (nonatomic, retain) NSNumber *parentToken;

- (redisCapability *) initWithString: (NSString *)str;
- (redisCapability *) initWithDictionary: (NSDictionary *)dict;

- (NSNumber *) createRandomNumber;

- (NSArray *)copyAttributesToArray: (NSArray *) capabilityArray;
@end
