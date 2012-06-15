// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "redisName.h"

@implementation redisName

@synthesize id;
@synthesize attributes;
@synthesize children;
@synthesize readCapability;
@synthesize writeCapability;

- (NSDictionary *)copyToDictionary {
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

	redisCapability *capability = [[[redisCapability alloc] init] autorelease];
	NSArray *readCapabilityArray = [capability copyAttributesToArray:readCapability];
	NSArray *writeCapabilityArray = [capability copyAttributesToArray:writeCapability];

	[dict setValue:id forKey:@"id"];

	if (attributes != nil) {
		redisAttribute *attrib = [[[redisAttribute alloc] init] autorelease];
		NSArray *attribArray = [attrib copyAttributesToArray:attributes];
		[dict setValue:attribArray forKey:@"attributes"];
		[attribArray release];
	}
	
	[dict setValue:children forKey:@"children"];
	[dict setValue:readCapabilityArray forKey:@"readCapability"];
	[dict setValue:writeCapabilityArray forKey:@"writeCapability"];

	NSDictionary *retValue = [[NSDictionary dictionaryWithDictionary:dict] retain];
	
	[readCapabilityArray release];
	[writeCapabilityArray release];
	[dict release];

    return retValue;
}
@end
