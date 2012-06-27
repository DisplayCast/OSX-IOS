// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "redisAttribute.h"

@implementation redisAttribute

@synthesize key;
@synthesize value;
@synthesize readCapability;
@synthesize writeCapability;

- (NSArray *)copyAttributesToArray: (NSArray *) attributesArray {
	NSMutableArray *array = [[NSMutableArray alloc] init];
	
	for (redisAttribute *attr in attributesArray) {
		NSDictionary *dict = [self copyAttributetoDictionary:attr];
		
		[array addObject:dict];
		
		[dict release];
	}
	
	NSArray *retValue = [[NSArray arrayWithArray:array] retain];
	[array release];
	
	return retValue;
}

- (NSDictionary *)copyAttributetoDictionary: (redisAttribute *)attr {
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	
	[dict setValue:[attr key] forKey:@"key"];
	[dict setValue:[attr value] forKey:@"value"];
	[dict setValue:[attr readCapability] forKey:@"readCapability"];
	[dict setValue:[attr writeCapability] forKey:@"writeCapability"];
	
	NSDictionary *retValue = [[NSDictionary dictionaryWithDictionary:dict] retain];
	[dict release];
	
    return retValue;
}
@end

