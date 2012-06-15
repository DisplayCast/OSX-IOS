	// Copyright (c) 2012, Fuji Xerox Co., Ltd.
	// All rights reserved.
	// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "NameServer.h"
#import "HTTPServer.h"
#import "Name.h"
#import "Capability.h"

#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>

@implementation NameServer
char *redisServer = NULL;
int redisPort = -1, redisDB = -1;

-(id) initWithRedisServer:(char *)server andPort:(int)port andDB:(int)db {
	self = [super init];

	redisServer = server;
	redisPort = port;
	redisDB = db;

	return self;
}

- (NSDictionary *) createName {
	NSString *nm = [self createGUID];
	redisCapability *rcapability = [[redisCapability alloc] init];
	redisCapability *wcapability = [[redisCapability alloc] init];
	NSDictionary *retValue = nil;
	
	[self openDB];
	
#ifdef USE_COREDATA
		// Store this in our database
	NSManagedObjectContext *context = managedObjectContext();
	NSEntityDescription *nameEntity = [NSEntityDescription entityForName:@"Name" inManagedObjectContext:context];
	Name *newName = [[Name alloc] initWithEntity:nameEntity insertIntoManagedObjectContext:context];
	
	/*
	 NSEntityDescription *wcEntity = [NSEntityDescription entityForName:@"Capability" inManagedObjectContext:context];
	 Capability *newWCapability = [[Capability alloc] initWithEntity:wcEntity insertIntoManagedObjectContext:context];
	 newWCapability.capability = wcapability;
	 
	 NSEntityDescription *rcEntity = [NSEntityDescription entityForName:@"Capability" inManagedObjectContext:context];
	 Capability *newRCapability = [[Capability alloc] initWithEntity:rcEntity insertIntoManagedObjectContext:context];
	 newRCapability.capability = rcapability;
	 
	 newName.id = nm;
	 
	 [[newName mutableSetValueForKey:@"writeCapability"] addObject:newWCapability];
	 [[newName mutableSetValueForKey:@"readCapability"] addObject:newRCapability];
	 */
	
	NSSet *w = [NSSet setWithObjects:wcapability, nil];
	newName.writeCapability = w;
	
	/*
	 [[NSSet alloc] initWithObjects:wcapability, nil];
	 newName.writeCapability = [NSSet setWithObject:w];
	 NSSet *r = [[NSSet alloc] initWithObjects:rcapability, nil];
	 newName.readCapability = [NSSet setWithObject:r];
	 */
#endif /* USE_COREDATA */
	
#ifdef USE_REDIS
	redisName *rn = [[redisName alloc] init];
	
	[rn setId:nm];
	[rn setReadCapability:[NSArray arrayWithObject:[rcapability description]]];
	[rn setWriteCapability:[NSArray arrayWithObject:[wcapability description]]];
	
	redisReply *reply = [self storeRedisName:rn];
	if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR))
		retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
	else {
			// Expire key, unless attributes or children are set
		if (redisCommand(rContext, "EXPIRE %s %d", [[rn id] UTF8String], REDIS_EXPIRE) == NULL)
			rContext = nil;
		
		retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nm, @"nm", [rcapability description], @"readCapability", [wcapability description], @"writeCapability", nil];
	}
	[rn release];
	[wcapability release];
	[rcapability release];
#endif /* USE_REDIS */
	
	[self saveDB];
	
	if (retValue == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
	else
		return (retValue);
}

- (NSDictionary *) addAttr:(NSString *)name withKey:(NSString *)key andValue:(NSString *)value withWriteCapability:(NSString *)capability {
	NSDictionary *retValue = nil;
	
	[self openDB];

#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if (rn == nil)
		retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
	else {
		BOOL accessAllowed = NO;	// We treat NO as unknown

			// Check whether access is denied at the key level
		for (redisAttribute *ra in [rn attributes]) {
			if ([[ra key] isEqualToString:key]) {
					// Usually, allowAccess function would consider this to give access. We need to differentiate between this condition and when no access is explicitly provided at this level
				if ([ra readCapability] != nil) {
					if ([self allowAccess:capability withPermission:[ra writeCapability]] == YES)
						accessAllowed = YES;
					else
						return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
				}
				break;
			}
		}
		
		if ((accessAllowed == YES) || ([self allowAccess:capability withPermission:[rn writeCapability]])) {
			if ([rn attributes] == nil) {
				NSMutableArray *array = [[NSMutableArray new] autorelease];
				[rn setAttributes:array];
				
				if (redisCommand(rContext, "PERSIST %s", [[rn id] UTF8String]) == NULL)
					rContext = nil;
			}
			
			BOOL modify = NO;
			for (redisAttribute *ra in [rn attributes]) {
				if ([[ra key] isEqualToString:key]) {
					[ra setValue:value];
					modify = YES;
					
					break;
				}
			}
			
			if (modify == NO) {
				redisAttribute *attr = [[redisAttribute alloc] init];
				[attr setKey:key];
				[attr setValue:value];
				
				[[rn attributes] addObject:attr];
				[attr release];
			}
			
			redisReply *reply = [self storeRedisName:rn];
			if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR))
				retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
			else
				retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
				// [rn release];
		} else
			retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
	}
#endif /* USE_REDIS */
	
	[self saveDB];
	
	if (retValue == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
	else
		return (retValue);
}

- (NSDictionary *) getAttr:(NSString *)name withKey:(NSString *)key withReadCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if ((rn == nil) || ([rn attributes] == nil))
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
	else {
		BOOL accessAllowed = NO;	// We treat NO as unknown

			// Check whether access is denied at the key level
		for (redisAttribute *ra in [rn attributes]) {
			if ([[ra key] isEqualToString:key]) {
					// Usually, allowAccess function would consider this to give access. We need to differentiate between this condition and when no access is explicitly provided at this level
				if ([ra readCapability] != nil) {
					if ([self allowAccess:capability withPermission:[ra readCapability]] == YES)
						accessAllowed = YES;
					else
						return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
				}
				break;
			}
		}
		
		if ((accessAllowed == YES) || ([self allowAccess:capability withPermission:[rn readCapability]])) {
			for (redisAttribute *ra in [rn attributes])
				if ([[ra key] isEqualToString:key])
					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", [ra value], @"value", nil];
			
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
		} else
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
	}
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

- (NSDictionary *) delAttr:(NSString *)name withKey:(NSString *)key withWriteCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if ((rn == nil) || ([rn attributes] == nil))
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
	else {
		if ([self allowAccess:capability withPermission:[rn writeCapability]]) {
			BOOL found = NO;
			redisAttribute *ra;
			for (ra in [rn attributes])
				if ([[ra key] isEqualToString:key]) {
					found =YES;
					break;
				}
			if (found == YES) {
				[[rn attributes] removeObject:ra];
				
				if ([[rn attributes] count] == 0) {
					[rn setAttributes:nil];

					if ([rn children] == nil) {
							// Expire key, unless attributes or children are set
						if (redisCommand(rContext, "EXPIRE %s %d", [[rn id] UTF8String], REDIS_EXPIRE) == NULL)
							rContext = nil;
					}
				}

				redisReply *reply = [self storeRedisName:rn];
				if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR))
					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
				else
					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
			} else
				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
		} else
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
	}
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

- (NSDictionary *) listAttrs:(NSString *)name withReadCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if ((rn == nil) || ([rn attributes] == nil))
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
	else {
		if ([self allowAccess:capability withPermission:[rn readCapability]]) {
			NSMutableArray *keys = [[[NSMutableArray alloc] init] autorelease];
			for (redisAttribute *ra in [rn attributes])
				[keys addObject:[ra key]];
			
			NSError *error = nil;
			NSData *json = [NSJSONSerialization dataWithJSONObject:keys options:0 error:&error];
			NSString *jsonStr = [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease];
			
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", jsonStr, @"keys", nil];
		} else
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
	}
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

- (NSDictionary *) addChild:(NSString *)name withChild:(NSString *)child withWriteCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:child];
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown child", @"error", nil];
	
	rn = [self getRedisName:name];
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	
	if ([self allowAccess:capability withPermission:[rn writeCapability]]) {
		if ([rn children] == nil) {
			NSMutableArray *array = [[[NSMutableArray alloc] init] autorelease];
			[rn setChildren:array];
			
			if (redisCommand(rContext, "PERSIST %s", [[rn id] UTF8String]) == NULL)
				rContext = nil;
		}
		
		[[rn children] addObject:child];
		
		redisReply *reply = [self storeRedisName:rn];
		if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR))
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
		else
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
	} else
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

- (NSDictionary *) delChild:(NSString *)name withChild:(NSString *)child withWriteCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	
	if ([self allowAccess:capability withPermission:[rn writeCapability]]) {
		if ([rn children] == nil)
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown child", @"error", nil];
		
		BOOL found = NO;
		NSString *curChild;
		for (curChild in [rn children])
			if ([child isEqualToString:curChild]) {
				found = YES;
				
				break;
			}
		if (found == NO)
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown child", @"error", nil];
		[[rn children] removeObject:curChild];
		
		if ([[rn children] count] == 0) {
			[rn setChildren:nil];

			if ([rn attributes] == nil) {
					// Expire key, unless attributes or children are set
				if (redisCommand(rContext, "EXPIRE %s %d", [[rn id] UTF8String], REDIS_EXPIRE) == NULL)
					rContext = nil;
			}
		}

		redisReply *reply = [self storeRedisName:rn];
		if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR))
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
		else
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
	} else
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

- (NSDictionary *) listChildren:(NSString *)name withReadCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	
	if ([self allowAccess:capability withPermission:[rn readCapability]]) {
		NSError *error = nil;
		NSArray *arr = ([rn children] == nil) ? [[[NSArray alloc] init] autorelease ]: [rn children];
		NSData *json = [NSJSONSerialization dataWithJSONObject:arr options:0 error:&error];
		
		NSString *jsonStr = [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease];
		
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", jsonStr, @"children", nil];
	} else
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

- (NSDictionary *)makeCapabilityWithCapability:(NSString *)name withKey:(NSString *)key forOperation:(NSString *)operation withWriteCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	redisAttribute *ra = nil;
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	
	BOOL accessAllowed = NO;	// We treat NO as unknown
	if (key != nil) {	// First check whether the key's capabilities allow for writing
		if ([rn attributes] == nil)
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
		
		BOOL found = NO;
		for (ra in [rn attributes]) {
			if ([[ra key] isEqualToString:key]) {
				found = YES;
				
					// Usually, allowAccess function would consider this to give access. We need to differentiate between this condition and when no access is explicitly provided at this level
				if ([ra writeCapability] != nil) {
					if ([self allowAccess:capability withPermission:[ra writeCapability]] == YES)
						accessAllowed = YES;
					else
						return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
				}
				break;
			}
		}
		if (found == NO)
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
	}
	
		// Don't know whether we have access yet
	if ((accessAllowed == NO) && ([self allowAccess:capability withPermission:[rn writeCapability]] != YES))
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
	
	redisCapability *rc = [[redisCapability alloc] init];
	
	[rc setCapabilityToken:[rc createRandomNumber]];
	
		// Autoreleasing parent causes a segfault in release()!!
	redisCapability *parent = [[redisCapability alloc] initWithString:capability];
	NSNumber *p = [[NSNumber alloc] initWithUnsignedLongLong:[[parent capabilityToken] unsignedLongLongValue]];
	[rc setParentToken:p];
	[p release];
	
	if (key != nil) {
		NSParameterAssert(ra != nil);
		
		if ([operation localizedCaseInsensitiveCompare:@"read"] == NSOrderedSame) {
			if ([ra readCapability] == nil)
				[ra setReadCapability:[[[NSMutableArray alloc] init] autorelease]];
			[(NSMutableArray *)[ra readCapability] addObject:rc];
		} else {
			if ([operation localizedCaseInsensitiveCompare:@"write"] == NSOrderedSame) {
				if ([ra writeCapability] == nil)
					[ra setWriteCapability:[[[NSMutableArray alloc] init] autorelease]];
				[(NSMutableArray *)[ra writeCapability] addObject:rc];
			} else {
				[rc release];
				
				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"operation unknown", @"error", nil];
			}
		}
	} else {
		if ([operation localizedCaseInsensitiveCompare:@"read"] == NSOrderedSame) {
			if ([rn readCapability] == nil)
				[rn setReadCapability:[[[NSMutableArray alloc] init] autorelease]];
			[[rn readCapability] addObject:rc];
		} else {
			if ([operation localizedCaseInsensitiveCompare:@"write"] == NSOrderedSame) {
				if ([rn writeCapability] == nil)
					[rn setWriteCapability:[[[NSMutableArray alloc] init] autorelease]];
				[[rn writeCapability] addObject:rc];
			} else {
				[rc release];
				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"operation unknown", @"error", nil];
			}
		}
	}
	
	redisReply *reply = [self storeRedisName:rn];
	if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR)) {
		[rc release];
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
	}
	
	NSString *madeCapability = [rc description];
	[rc release];
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", madeCapability, @"capability", nil];
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

- (NSDictionary *)revokeCapability:(NSString *)name withKey:(NSString *)key forOperation:(NSString *)operation revokeCapability:(NSString *)revokeCapability withWriteCapability:(NSString *)capability {

#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	redisAttribute *ra = nil;
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	
	BOOL accessAllowed = NO;	// We treat NO as unknown
	if (key != nil) {	// First check whether the key's capabilities allow for writing
		if ([rn attributes] == nil)
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
		
		BOOL found = NO;
		for (ra in [rn attributes]) {
			if ([[ra key] isEqualToString:key]) {
				found = YES;
				
					// Usually, allowAccess function would consider this to give access. We need to differentiate between this condition and when no access is explicitly provided at this level
				if ([ra writeCapability] != nil) {
					if ([self allowAccess:capability withPermission:[ra writeCapability]] == YES)
						accessAllowed = YES;
					else
						return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
				}
				break;
			}
		}
		if (found == NO)
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
	}
	
		// Don't know whether we have access yet
	if ((accessAllowed == NO) && ([self allowAccess:capability withPermission:[rn writeCapability]] != YES))
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];

		// We have the capability to revoke - now lets do it
		// Revoking a key-capability would mean that we check all other cloned capabilities that used this key.
		// Revoking a name capability means that we should revoke all cloned name-capabilities and key-capabilities

	if (key != nil) {
		NSParameterAssert(ra != nil);
		
		if ([operation localizedCaseInsensitiveCompare:@"read"] == NSOrderedSame) {
			if ([ra readCapability] == nil)
				[ra setReadCapability:[[[NSMutableArray alloc] init] autorelease]];
			[(NSMutableArray *)[ra readCapability] addObject:rc];
		} else {
			if ([operation localizedCaseInsensitiveCompare:@"write"] == NSOrderedSame) {
				if ([ra writeCapability] == nil)
					[ra setWriteCapability:[[[NSMutableArray alloc] init] autorelease]];
				[(NSMutableArray *)[ra writeCapability] addObject:rc];
			} else {
				[rc release];
				
				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"operation unknown", @"error", nil];
			}
		}
	} else {
		if ([operation localizedCaseInsensitiveCompare:@"read"] == NSOrderedSame) {
			if ([rn readCapability] == nil)
				[rn setReadCapability:[[[NSMutableArray alloc] init] autorelease]];
			[[rn readCapability] addObject:rc];
		} else {
			if ([operation localizedCaseInsensitiveCompare:@"write"] == NSOrderedSame) {
				if ([rn writeCapability] == nil)
					[rn setWriteCapability:[[[NSMutableArray alloc] init] autorelease]];
				[[rn writeCapability] addObject:rc];
			} else {
				[rc release];
				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"operation unknown", @"error", nil];
			}
		}
	}
	
	redisReply *reply = [self storeRedisName:rn];
	if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR)) {
		[rc release];
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
	}
	
	NSString *madeCapability = [rc description];
	[rc release];
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", madeCapability, @"capability", nil];
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}
@end

@implementation NameServer (DataStorage)
#ifdef USE_COREDATA
static NSManagedObjectModel *managedObjectModel() {
    static NSManagedObjectModel *model = nil;
    if (model != nil)
        return model;
	
	NSString *path = @"NameServer";
	path = [path stringByDeletingPathExtension];
    NSURL *modelURL = [NSURL fileURLWithPath:[path stringByAppendingPathExtension:@"momd"]];
    model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
	
    return model;
}

static NSManagedObjectContext *managedObjectContext() {
    static NSManagedObjectContext *context = nil;
    if (context != nil)
        return context;
	
    @autoreleasepool {
		context = [[NSManagedObjectContext alloc] init];
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel()];
        [context setPersistentStoreCoordinator:coordinator];
		
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
		NSString *path = [[NSString stringWithFormat:@"%@/NameServer", [paths objectAtIndex:0]] stringByDeletingPathExtension];
		if (access([path UTF8String], O_RDWR | O_DIRECTORY) == -1)
			mkdir([path UTF8String], 0700);
		
		NSString *dbPath = [[NSString stringWithFormat:@"%@/names", path] stringByAppendingPathExtension:@"sqlite"];
        NSURL *url = [NSURL fileURLWithPath:dbPath];
		
		NSError *error;
        NSPersistentStore *newStore = [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error];
        
        if (newStore == nil) {
            NSLog(@"Store Configuration Failure %@", ([error localizedDescription] != nil) ? [error localizedDescription] : @"Unknown Error");
			
			exit(1);
        }
		[newStore release];
    }
    return context;
}
#endif /* USE_COREDATA */

- (void) dumpDB {
#ifdef USE_COREDATA
		// Create the managed object context
	NSManagedObjectContext *context = managedObjectContext();
	
		// Custom code here...
		// Save the managed object context
	NSEntityDescription *nameEntity = [NSEntityDescription entityForName:@"Name" inManagedObjectContext:context];
	
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	[request setEntity:nameEntity];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id == %@", @"21EC2020-3AEA-1069-A2DD-08002B30309D"];
	[request setPredicate:predicate];
	
	NSError *error = nil;
	NSArray *array = [context executeFetchRequest:request error:&error];
	NSLog(@"Retrieved: %ld records", [array count]);
	for (Name *nm in array) {
		NSLog(@"Entries are: %@", nm.id);
	}
	[request release];
#endif /* USE_COREDATA */
}

#if 0
	// NSManagedObject *newName = [NSEntityDescription insertNewObjectForEntityForName:@"Name" inManagedObjectContext:context];
Name *newName = [[Name alloc] initWithEntity:nameEntity insertIntoManagedObjectContext:context];

[newName setId:@"21EC2020-3AEA-1069-A2DD-08002B30309D"];
#endif

- (void) openDB {
#ifdef USE_COREDATA
	managedObjectContext();
#endif
	
#ifdef USE_REDIS
	if (rContext != nil)
		return;

	struct timeval timeout = { 1, 500000 }; // 1.5 seconds
    rContext = redisConnectWithTimeout((char*)redisServer, redisPort, timeout);
	if (rContext -> err) {
		NSLog(@"ERROR: Cannot connect to redis server at %s:%d. Error is: %s", redisServer, redisPort, rContext->errstr);
		rContext = NULL;
	}
	redisReply *reply = redisCommand(rContext, "SELECT %d", redisDB);
	if (reply == NULL) {
		rContext = NULL;
		return;
	}

	reply = redisCommand(rContext, "DBSIZE");
	if (reply == NULL) {
		rContext = NULL;
		return;
	}
	if ((reply != NULL) && (reply->type == REDIS_REPLY_INTEGER))
		NSLog(@"DEBUG: Name space contains: %lld names", reply->integer);
#endif
	
}

- (void) saveDB {
#ifdef USE_COREDATA
	NSManagedObjectContext *context = managedObjectContext();
	NSError *error = nil;
	
	@try {
		if (![context save:&error]) {
			NSLog(@"Error while saving %@", ([error localizedDescription] != nil) ? [error localizedDescription] : @"Unknown Error");
			
			exit(1);
		}
	} @catch (NSException *e) {
		
	}
#endif /* USE_COREDATA */
}
@end


@implementation NameServer (Utilities)
- (NSString *) createGUID {
	
	return [[NSProcessInfo processInfo] globallyUniqueString];
}

- (BOOL) allowAccess: (NSString *)capability withPermission:(NSArray *)capabilities {
	if (capabilities == nil)
		return TRUE;
	
	redisCapability *cap = [[[redisCapability alloc] initWithString:capability] autorelease];
	
	for (redisCapability *c in capabilities) {
			// redisCapability *cc = [[[redisCapability alloc] initWithString:c] autorelease];
		
		if ([[cap capabilityToken] isEqualToNumber:[c capabilityToken]])
			return TRUE;
	}
	
	return FALSE;
}

#ifdef USE_REDIS

- (NSMutableArray *)parseDictArray: (NSArray *)ad {
	if ( ad != nil) {
		NSMutableArray *retValue = [[[NSMutableArray alloc] init] autorelease];
		
		for (id elem in ad) {
			redisCapability *rc = nil;
			
			if ([elem isKindOfClass:[NSDictionary class]])
				rc = [[[redisCapability alloc] initWithDictionary:(NSDictionary *)elem] autorelease];
			
			if ([elem isKindOfClass:[NSString class]])
				rc = [[[redisCapability alloc] initWithString:(NSString *)elem] autorelease];
			
			if (rc != nil)
				[retValue addObject:rc];
		}
		return retValue;
	} else
		return nil;
}

	// retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS GET failed", @"error", nil];

	// Get the redisName object from the redis key:value store
- (redisName *) getRedisName: (NSString *)name {
	redisName *retValue;
	
	[self openDB];
	
	redisReply *reply = redisCommand(rContext, "GET %s", [name UTF8String]);
	if (reply == NULL)
		rContext = nil;

	if ((reply == NULL) || (reply->type != REDIS_REPLY_STRING))
		retValue = nil;
	else {
			// NSLog(@"DEBUG: Read value: %s", reply->str);
		NSString *repString = [[NSString alloc] initWithCString:(reply->str) encoding:[NSString defaultCStringEncoding]];
		NSData *repData = [repString dataUsingEncoding:NSUTF8StringEncoding];
		[repString release];
		
		NSError *error = nil;
		
		NSMutableDictionary *dict = [NSJSONSerialization JSONObjectWithData:repData options:NSJSONReadingMutableContainers error:&error];
		
		retValue = [[[redisName alloc] init] autorelease];
		
		NSString *val = [dict objectForKey:@"id"]; if (val != nil) [retValue setId:val];
		
		NSMutableArray *array = [dict objectForKey:@"attributes"];
		if (array != nil ) {
			NSMutableArray *redisAttributes = [[NSMutableArray alloc] init];
			
			for (NSDictionary *elem in array) {
				redisAttribute *ra = [[redisAttribute alloc] init];
				
				[ra setKey:[elem objectForKey:@"key"]];
				[ra setValue:[elem objectForKey:@"value"]];
				
				NSArray *rca = [elem objectForKey:@"readCapability"];
				if (rca != nil)
					[ra setReadCapability:[self parseDictArray:rca]];
				
				NSArray *wca = [elem objectForKey:@"writeCapability"];
				if ( wca != nil)
					[ra setWriteCapability:[self parseDictArray:wca]];
				
				[redisAttributes addObject:ra];
				[ra release];
			}
			[retValue setAttributes:redisAttributes];
			
			[redisAttributes release];
		}
		
		array = [dict objectForKey:@"children"]; if (array != nil) [retValue setChildren:array];
		
		NSArray *rca = [dict objectForKey:@"readCapability"];
		if (rca != nil)
			[retValue setReadCapability:[self parseDictArray:rca]];
		
		NSArray *wca = [dict objectForKey:@"writeCapability"];
		if ( wca != nil)
			[retValue setWriteCapability:[self parseDictArray:wca]];
	}
	freeReplyObject(reply);
	
	return retValue;
}

- (redisReply *) storeRedisName: (redisName *)rn {
	NSError *error = nil;
	NSDictionary *jsonDict = [rn copyToDictionary];
	NSData *json = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&error];
	NSString *jsonStr = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
	
	NSLog(@"DEBUG: Storing JSON object %@", jsonStr);
	
	redisReply *reply = redisCommand(rContext, "SET %s %s", [[rn id] UTF8String], [jsonStr UTF8String]);
	if (reply == NULL)
		rContext = nil;
	[jsonDict release];
	[jsonStr release];
	
	return reply;
}
#endif /* USE_REDIS */

@end

@implementation NameServer (HTTPRest)
HTTPServer *server;

- (void) HTTPServer:server didMakeNewConnection:connection {
#pragma unused(server, connection)
		// NSLog(@"DEBUG: didMakeNewConnection: %@", connection);
}

- (void) HTTPConnection:connection didReceiveRequest:(HTTPServerRequest *)mess {
#pragma unused(connection)
	
	@autoreleasepool {
		CFHTTPMessageRef request = [mess request];
		NSString *method = [(id)CFHTTPMessageCopyRequestMethod(request) autorelease];
		
		if (!method) {
			CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 400, NULL, kCFHTTPVersion1_1); // Bad Request
			[mess setResponse:response];
			CFRelease(response);
			return;
		}
		
		if ([method isEqual:@"GET"] || [method isEqual:@"HEAD"]) {
			NSURL *uri = (NSURL *)CFHTTPMessageCopyRequestURL(request);
			NSString *command = [uri path];
			NSDictionary *query = [uri queryComponents];
			
			id responseObj = nil;
			
			if ([command localizedCaseInsensitiveCompare:@"/CREATENAME"] == NSOrderedSame) {
				responseObj = [self createName];
			} else if ([command localizedCaseInsensitiveCompare:@"/ADDATTR"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *key = [query objectForKey:@"KEY"] ;
				NSArray *value = [query objectForKey:@"VALUE"];
				NSArray *name = [query objectForKey:@"NAME"];
				
				if (! ((name == nil) || (key == nil) || (value == nil)))
					responseObj = [self addAttr:[name objectAtIndex:0] withKey:[key objectAtIndex:0] andValue:[value objectAtIndex:0] withWriteCapability:[capability objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/GETATTR"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *key = [query objectForKey:@"KEY"] ;
				NSArray *name = [query objectForKey:@"NAME"];
				
				if (! ((name == nil) || (key == nil)))
					responseObj = [self getAttr:[name objectAtIndex:0] withKey:[key objectAtIndex:0] withReadCapability:[capability objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/DELATTR"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *key = [query objectForKey:@"KEY"] ;
				NSArray *name = [query objectForKey:@"NAME"];
				
				if (! ((name == nil) || (key == nil)))
					responseObj = [self delAttr:[name objectAtIndex:0] withKey:[key objectAtIndex:0] withWriteCapability:[capability objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/LISTATTRS"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *name = [query objectForKey:@"NAME"];
				
				if (name != nil)
					responseObj = [self listAttrs:[name objectAtIndex:0] withReadCapability:[capability objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/ADDCHILD"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *name = [query objectForKey:@"NAME"];
				NSArray *child = [query objectForKey:@"CHILD"];
				
				if (! ((name == nil) || (child == nil)))
					responseObj = [self addChild:[name objectAtIndex:0] withChild:[child objectAtIndex:0] withWriteCapability:[capability objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/DELCHILD"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *name = [query objectForKey:@"NAME"];
				NSArray *child = [query objectForKey:@"CHILD"];
				
				if (! ((name == nil) || (child == nil)))
					responseObj = [self delChild:[name objectAtIndex:0] withChild:[child objectAtIndex:0] withWriteCapability:[capability objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/LISTCHILDREN"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *name = [query objectForKey:@"NAME"];
				
				if (name != nil)
					responseObj = [self listChildren:[name objectAtIndex:0] withReadCapability:[capability objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/MAKECAPABILITY"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *name = [query objectForKey:@"NAME"];
				NSArray *key = [query objectForKey:@"KEY"];
				NSArray *operation = [query objectForKey:@"OPERATION"];
				
				if (! ((name == nil) || (operation == nil) || (capability == nil)))
					responseObj = [self makeCapabilityWithCapability:[name objectAtIndex:0] withKey:((key == nil) ? key:[key objectAtIndex:0]) forOperation:[operation objectAtIndex:0] withWriteCapability:[capability objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/REVOKECAPABILITY"] == NSOrderedSame) {
				NSArray *capability = [query objectForKey:@"CAPABILITY"]; // write capability of NULL is still valid. Perhaps it is a public'ly writeable name
				NSArray *rcapability = [query objectForKey:@"REVOKE"]; 
				NSArray *name = [query objectForKey:@"NAME"];
				NSArray *key = [query objectForKey:@"KEY"];
				NSArray *operation = [query objectForKey:@"OPERATION"];
				
				if (! ((name == nil) || (operation == nil) || (capability == nil) || (rcapability == nil)))
					responseObj = [self revokeCapability:[name objectAtIndex:0] withKey:((key == nil) ? key:[key objectAtIndex:0]) forOperation:[operation objectAtIndex:0] revokeCapability:[rcapability objectAtIndex:0] withWriteCapability:[capability objectAtIndex:0]];
			}
			
				// Finished processing. Now response to the query
			[uri release];
			
				// One of our methods created the correct response
			if (responseObj != nil) {
				CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 200, NULL, kCFHTTPVersion1_1); // OK
				CFHTTPMessageSetHeaderFieldValue(response, (CFStringRef)@"Content-Type", (CFStringRef) @"application/json");
				
				if ([method isEqual:@"GET"]) {
					NSError *error = [[NSError alloc] init];
					NSData *jsonData = [NSJSONSerialization dataWithJSONObject:responseObj options:NSJSONWritingPrettyPrinted error:&error];
					[error release];
					
					CFHTTPMessageSetBody(response, (CFDataRef)jsonData);
					CFHTTPMessageSetHeaderFieldValue(response, (CFStringRef)@"Content-Length", (CFStringRef)[NSString stringWithFormat:@"%lu", [jsonData length]]);
						// [jsonData release];
				}
				
				[mess setResponse:response];
				
					// CFRelease(responseObj);
				CFRelease(response);
				
				return;
			}
			
				// Undefined command
			CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 400, NULL, kCFHTTPVersion1_1); // Bad Request
			NSParameterAssert(response);
			[mess setResponse:response];
			CFRelease(response);
			return;
		}
		
			// We do not support POST, DELETE etc.
		CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 405, NULL, kCFHTTPVersion1_1); // Method Not Allowed
		NSParameterAssert(response);
		[mess setResponse:response];
		CFRelease(response);
	}
}

- (id) init {
	self = [super init];
	
	[self openDB];
	
	server = [[HTTPServer alloc] init];
	[server setPort:9999];
	
	return self;
}

- (void) start {
	NSError *startError = nil;
	if ([server start:&startError]) {
		[server setDelegate:self];
	} else {
		NSLog(@"Error starting HTTP server: %@", startError);
		server = nil;
	}
}
@end

@implementation NSString (XQueryComponents)
- (NSString *)stringByDecodingURLFormat {
    NSString *result = [self stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    result = [result stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return result;
}

- (NSString *)stringByEncodingURLFormat {
    NSString *result = [self stringByReplacingOccurrencesOfString:@" " withString:@"+"];
    result = [result stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return result;
}

- (NSMutableDictionary *)dictionaryFromQueryComponents {
    NSMutableDictionary *queryComponents = [NSMutableDictionary dictionary];
    for(NSString *keyValuePairString in [self componentsSeparatedByString:@"&"]) {
        NSArray *keyValuePairArray = [keyValuePairString componentsSeparatedByString:@"="];
        if ([keyValuePairArray count] < 2) continue; // Verify that there is at least one key, and at least one value.  Ignore extra = signs
        NSString *key = [[[keyValuePairArray objectAtIndex:0] stringByDecodingURLFormat] uppercaseString];
        NSString *value = [[keyValuePairArray objectAtIndex:1] stringByDecodingURLFormat];
        NSMutableArray *results = [queryComponents objectForKey:key]; // URL spec says that multiple values are allowed per key
        if(!results) { // First object
            results = [NSMutableArray arrayWithCapacity:1];
            [queryComponents setObject:results forKey:key];
        }
        [results addObject:value];
    }
    return queryComponents;
}
@end

@implementation NSURL (XQueryComponents)
- (NSMutableDictionary *)queryComponents {
    return [[self query] dictionaryFromQueryComponents];
}
@end

@implementation NSDictionary (XQueryComponents)
- (NSString *)stringFromQueryComponents {
    NSString *result = nil;
    for(NSString *key in [self allKeys]) {
        key = [key stringByEncodingURLFormat];
        NSArray *allValues = [self objectForKey:key];
        if([allValues isKindOfClass:[NSArray class]])
            for(NSString *value in allValues) {
                value = [[value description] stringByEncodingURLFormat];
                if(!result)
                    result = [NSString stringWithFormat:@"%@=%@",key,value];
                else 
                    result = [result stringByAppendingFormat:@"&%@=%@",key,value];
			} else {
				NSString *value = [[allValues description] stringByEncodingURLFormat];
				if(!result)
					result = [NSString stringWithFormat:@"%@=%@",key,value];
				else 
					result = [result stringByAppendingFormat:@"&%@=%@",key,value];
			}
    }
    return result;
}
@end

