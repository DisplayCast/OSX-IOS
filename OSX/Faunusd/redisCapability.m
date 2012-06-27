// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "redisCapability.h"

@implementation redisCapability
@synthesize capabilityToken;
@synthesize parentToken;

- (NSString *)description {
	return [NSString stringWithFormat:@"%@-%@", parentToken, capabilityToken];
}

- (redisCapability *) initWithDictionary: (NSDictionary *)dict {
	NSParameterAssert([dict isKindOfClass:[NSDictionary class]]);

	NSNumber *num = [dict objectForKey:@"parent"];
	NSParameterAssert(num != nil);
	NSParameterAssert([num isKindOfClass:[NSNumber class]]);
	parentToken = num;

	num = [dict objectForKey:@"capability"];
	NSParameterAssert(num != nil);
	NSParameterAssert([num isKindOfClass:[NSNumber class]]);
	capabilityToken = num;

	return self;
}

- (redisCapability *) initWithString: (NSString *)str {
	NSParameterAssert([str isKindOfClass:[NSString class]]);

	NSArray *components = [str componentsSeparatedByString:@"-"];

	if ([components count] == 2) {
		parentToken = [NSNumber numberWithUnsignedLongLong:strtoull([[components objectAtIndex:0] UTF8String], NULL, 0)];
		capabilityToken = [NSNumber numberWithUnsignedLongLong:strtoull([[components objectAtIndex:1] UTF8String], NULL, 0)];

		return self;
	} else
		return nil;
}

- (id) init {
	self = [super init];

	capabilityToken = [self createRandomNumber];
	parentToken = [NSNumber numberWithUnsignedLongLong:0];

	return self;
}

- (NSNumber *) createRandomNumber {
	NSNumber *randomNumber;
	unsigned long long retValue = arc4random();

	NSParameterAssert(sizeof(unsigned long long) == 8);

		// We use 0 for the case of "none - for a parent"
	do {
		retValue = retValue << 32;
		retValue += arc4random();
	} while (retValue == 0);

	randomNumber = [NSNumber numberWithUnsignedLongLong:retValue];

	return randomNumber;
}

- (NSArray *)copyAttributesToArray: (NSArray *) capabilityArray {
	NSMutableArray *array = [[NSMutableArray alloc] init];
	
	for (redisCapability *cap in capabilityArray) {
		if ([cap isKindOfClass:[NSString class]])
			[array addObject:cap];
		else {
			NSDictionary *dict = [self copyCapabilitytoDictionary:cap];
		
			[array addObject:dict];
		
			[dict release];
		}
	}
	
	NSArray *retValue = [[NSArray arrayWithArray:array] retain];
	[array release];
	
	return retValue;
}

- (NSDictionary *)copyCapabilitytoDictionary: (redisCapability *)cap {
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

	[dict setValue:[cap capabilityToken] forKey:@"capability"];
	[dict setValue:[cap parentToken ] forKey:@"parent"];
	
	NSDictionary *retValue = [[NSDictionary dictionaryWithDictionary:dict] retain];
	[dict release];
	
    return retValue;
}
@end
