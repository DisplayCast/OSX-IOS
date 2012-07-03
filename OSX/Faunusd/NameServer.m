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

#ifdef USE_REDIS
char *redisServer = NULL;
int redisPort = -1, redisDB = -1;
static redisContext *rContext;

HTTPServer *server;

/*!
 @method initWithRedisServer
 @param redisServer
 @param redisServerPort
 @param redisdatabase

 initializer that is configured from the command line.
 we don't support authentication with the redis server though that should be trivial with the AUTH command to the redis server
 */

-(id) initWithRedisServer:(char *)rserver andPort:(int)port andDB:(int)db {
	self = [super init];

	redisServer = rserver;
	redisPort = port;
	redisDB = db;

	[self openDB];

	server = [[HTTPServer alloc] init];
	[server setPort:9999];

	return self;
}
#endif /* USE_REDIS */

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

/*!
 @method createName
 
 Names are basically a GUID string. By default, we create a read and write capability and return them via JSON response. 
 To make the name globally readable, revoke the read capability. To make it globally writeable, revoke the write capability
 
 */
- (NSDictionary *) createName {
	NSString *nm = [self createGUID];
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
	redisCapability *rcapability = [[redisCapability alloc] init];
	redisCapability *wcapability = [[redisCapability alloc] init];
	redisName *rn = [[redisName alloc] init];
	
	[rn setId:nm];
	[rn setReadCapability:[NSArray arrayWithObject:[rcapability description]]];
	[rn setWriteCapability:[NSArray arrayWithObject:[wcapability description]]];
	
	redisReply *reply = [self storeRedisName:rn];
	if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR)) {
		if (reply != NULL)
			freeReplyObject(reply);

		retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
	} else {
		freeReplyObject(reply);
			// Expire key, unless attributes or children are set
		if ((reply = redisCommand(rContext, "EXPIRE %s %d", [[rn id] UTF8String], REDIS_EXPIRE)) == NULL)
			rContext = nil;
		else
			freeReplyObject(reply);
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

/*!
 
 @method: addAttr
 @param: name
 @param: key
 @param: value
 @param: writeCapability
 
 add/modify the <key:value> attribute to the given name. The operation requires write capability. 
 To add a new key:value pair, one needs write capability on the name. To modify a key:value attribute, one needs the write capability on the key:value. If no capability exists for a particular key, then one needs the write capability of the name. If some capabilities exist, then not matching with those is a access violation, even though one has the name write capability.
 */

- (NSDictionary *) addAttr:(NSString *)name withKey:(NSString *)key andValue:(NSString *)value withWriteCapability:(NSString *)capability {
	NSDictionary *retValue = nil;
	
	[self openDB];

#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if (rn == nil)
		retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	else {
		BOOL accessAllowed = NO;	// We treat NO as unknown
		redisAttribute *modifyAttr = nil;

		for (redisAttribute *ra in [rn attributes]) {
			// Check whether access is denied at the key level
			if ([[ra key] isEqualToString:key]) {
				modifyAttr = ra;

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
		
		if ((accessAllowed == YES) || ([self allowAccess:capability withPermission:[rn writeCapability]])) {
			if ([rn attributes] == nil) {
				NSMutableArray *array = [[NSMutableArray new] autorelease];
				[rn setAttributes:array];

				redisReply *reply;
					// Now that a new key:value attribute is added, the name will no longer be auto expired
				if ((reply = redisCommand(rContext, "PERSIST %s", [[rn id] UTF8String])) == NULL)
					rContext = nil;
				else
					freeReplyObject(reply);
			}

				// Add or modify
			if (modifyAttr == nil) {
				redisAttribute *attr = [[redisAttribute alloc] init];
				[attr setKey:key];
				[attr setValue:value];
				
				[[rn attributes] addObject:attr];
				[attr release];
			} else {
				[modifyAttr setValue:value];
			}

				// Store the updated name entry in REDIS
			redisReply *reply = [self storeRedisName:rn];
			if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR))
				retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
			else
				retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
			if (reply != NULL)
				freeReplyObject(reply);
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

/*!
 
 @method: getattr
 @param: name
 @param: key
 @param: readCapability

 Gets the value for a particular 'key' for the 'name'. If read capability for the key exists, then we require a match with out capability. Otherwise, a read capability on the name would suffice. 
 
 */
- (NSDictionary *) getAttr:(NSString *)name withKey:(NSString *)key withReadCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if ((rn == nil) || ([rn attributes] == nil))
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	else {
		BOOL accessAllowed = NO;	// We treat NO as unknown
		redisAttribute *ra = nil;
		BOOL keyFound = NO;

			// Check whether access is denied at the key level
		for (ra in [rn attributes]) {
			if ([[ra key] isEqualToString:key]) {
				keyFound = YES;
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

		if (keyFound == NO)
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];

			// Access for either granted at the key level or at the name level
		if ((accessAllowed == YES) || ([self allowAccess:capability withPermission:[rn readCapability]]))
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", [ra value], @"value", nil];
		else
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
	}
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

/*!

 @method: delattr
 @param: name
 @param: key
 @param: writeCapability

 Deletes a particular 'key' for the 'name'. Requires a write capability on the name.

 */
- (NSDictionary *) delAttr:(NSString *)name withKey:(NSString *)key withWriteCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if ((rn == nil) || ([rn attributes] == nil))
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	else {
		if ([self allowAccess:capability withPermission:[rn writeCapability]]) {
			BOOL found = NO;
			redisAttribute *ra;
			for (ra in [rn attributes])
				if ([[ra key] isEqualToString:key]) {
					found = YES;
					break;
				}

			if (found == YES) {
				[[rn attributes] removeObject:ra];

					// If no other attributes let, cleanup the attributes array and start the xpiration clock if no children exist
				if ([[rn attributes] count] == 0) {
					[rn setAttributes:nil];

					if ([rn children] == nil) {
						redisReply *reply;
							// Expire key, unless attributes or children are set
						if ((reply = redisCommand(rContext, "EXPIRE %s %d", [[rn id] UTF8String], REDIS_EXPIRE)) == NULL)
							rContext = nil;
						else
							freeReplyObject(reply);
					}
				}

					// Save the updates to the redis server
				redisReply *reply = [self storeRedisName:rn];
				if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR)) {
					if (reply != NULL)
						freeReplyObject(reply);

					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
				} else {
					freeReplyObject(reply);

					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
				}

			} else
				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown key", @"error", nil];
		} else
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
	}
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

/*!

 @method: listAttrs
 @param: name
 @param: readCapability

 Lists all the attributes for a given name. Requires read capability on the name. Note that we return attributes whose values might not be accessible to a particular user. I suppose we could give all the read capabilities to the system and then have it sort out and return only attributes that are readable. For an intranet, our current model is okay (and is much easier to implement). Otherwise, we have to try with each capability and then create a union of all attributes allowed by each capability!!

 */
- (NSDictionary *) listAttrs:(NSString *)name withReadCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if ((rn == nil) || ([rn attributes] == nil))
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	else {
		if ([self allowAccess:capability withPermission:[rn readCapability]]) {
			NSMutableArray *keys = [[[NSMutableArray alloc] init] autorelease];
			for (redisAttribute *ra in [rn attributes])
				[keys addObject:[ra key]];

				// Now create a JSON response of the keys
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

/*!

 @method: addChild
 @param: name
 @param: child
 @param: writeCapability

 If write capability on the name exists, then add the new child into the collection of children.

 */
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

			redisReply *reply;
				// Now that we have children, the name will persist
			if ((reply = redisCommand(rContext, "PERSIST %s", [[rn id] UTF8String])) == NULL)
				rContext = nil;
			else
				freeReplyObject(reply);
		}

		NSParameterAssert([rn children] != nil);

		[[rn children] addObject:child];

			// Now store the new entry in the redis storage
		redisReply *reply = [self storeRedisName:rn];
		if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR)) {
			if (reply != NULL)
				freeReplyObject(reply);
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
		} else {
			freeReplyObject(reply);

			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
		}
	} else
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

/*!

 @method: delchild
 @param: name
 @param: child
 @param: writeCapability

 Deletes a particular 'child' for the 'name'. Requires a write capability on the name.

 */
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

			// If no children or attributes, then start the expiration clock. Given that redis does not support atomic transactions, should we first remove persistence before ensuring that the objects has been saved?
		if ([[rn children] count] == 0) {
			[rn setChildren:nil];

			if ([rn attributes] == nil) {
				redisReply *reply;
					// Expire key, unless attributes or children are set
				if ((reply = redisCommand(rContext, "EXPIRE %s %d", [[rn id] UTF8String], REDIS_EXPIRE)) == NULL)
					rContext = nil;
				else
					freeReplyObject(reply);
			}
		}

		redisReply *reply = [self storeRedisName:rn];
		if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR)) {
			if (reply != NULL)
				freeReplyObject(reply);
			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
		} else {
			freeReplyObject(reply);

			return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
		}
	} else
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusENOACCESS], @"status", @"Access denied", @"error", nil];
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

/*!

 @method: listChildren
 @param: name
 @param: key
 @param: writeCapability

 Returns a JSON list of all the children (as long as have read capabiity on the name

 */
- (NSDictionary *) listChildren:(NSString *)name withReadCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];

		// Even if there are no children, we don't disclose it unless we have the correct read capability
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

/*!

 @method: makeCapabilityWithCapability
 @param: name
 @param: key
 @param: operation - "read" or "write"
 @param: writeCapability

 If we have the write capability on the key (or name), we clone our read/write capability.

 */
- (NSDictionary *)makeCapabilityWithCapability:(NSString *)name withKey:(NSString *)key forOperation:(NSString *)operation withWriteCapability:(NSString *)capability {
	[self openDB];
	
#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	
	BOOL accessAllowed = NO;	// We treat NO as unknown
	redisAttribute *ra = nil;

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

		// Now, save the name update
	redisReply *reply = [self storeRedisName:rn];
	if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR)) {
		[rc release];
		if (reply != NULL)
			freeReplyObject(reply);
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
	}

		// Return a human readable form
	NSString *madeCapability = [rc description];
	[rc release];
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", madeCapability, @"capability", nil];
#endif /* USE_REDIS */
	
	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

/*!

 @method: revokeCapability
 @param: name
 @param: key
 @param: operation - "read" or "write"
 @param: revokeCapability - capability to be revoked
 @param: writeCapability

 If we have the write capability on the key (or name), we revoke our read/write capability.

 */
- (NSDictionary *)revokeCapability:(NSString *)name withKey:(NSString *)key forOperation:(NSString *)operation revokeCapability:(NSString *)revokeCapability withWriteCapability:(NSString *)capability {

#ifdef USE_REDIS
	redisName *rn = [self getRedisName:name];
	if (rn == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown name", @"error", nil];
	
	BOOL accessAllowed = NO;	// We treat NO as unknown
	redisAttribute *ra = nil;

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

	redisCapability *revoke = [[redisCapability alloc] initWithString:revokeCapability];
	BOOL revoked = NO;

		// We have the capability to revoke - now lets do it
		// Revoking a key-capability would mean that we check all other cloned capabilities that used this key.
		// Revoking a name capability means that we should revoke all cloned name-capabilities and key-capabilities

	if (key != nil) {
		NSParameterAssert(ra != nil);

		if ([operation localizedCaseInsensitiveCompare:@"read"] == NSOrderedSame) {
			if ([ra readCapability] == nil) {
				[revoke release];

				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown capability", @"error", nil];
			}

				// Search the key's read capabilities
			for (redisCapability *rc in [ra readCapability]) {
				if ([[revoke capabilityToken] isEqualToNumber:[rc capabilityToken]]) {
					[[ra readCapability] removeObject:rc];
					revoked = YES;

					break;
				}
			}

			if (revoked == NO) {
				[revoke release];

				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown capability", @"error", nil];
			}
		} else {
			if ([operation localizedCaseInsensitiveCompare:@"write"] == NSOrderedSame) {
				if ([ra writeCapability] == nil) {
					[revoke release];
					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown capability", @"error", nil];
				}

					// Search the key's read capabilities
				for (redisCapability *rc in [ra writeCapability]) {
					if ([[revoke capabilityToken] isEqualToNumber:[rc capabilityToken]]) {
						[[ra writeCapability] removeObject:rc];
						revoked = YES;

						break;
					}
				}

				if (revoked == NO) {
					[revoke release];

					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown capability", @"error", nil];
				}
			} else {
				[revoke release];

				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"operation unknown", @"error", nil];
			}
		}
	} else {
			// Revoke the name capability
		if ([operation localizedCaseInsensitiveCompare:@"read"] == NSOrderedSame) {
			if ([rn readCapability] == nil)
				[rn setReadCapability:[[[NSMutableArray alloc] init] autorelease]];

				// Search the key's read capabilities
			for (redisCapability *rc in [rn readCapability]) {
				if ([[revoke capabilityToken] isEqualToNumber:[rc capabilityToken]]) {
					[[rn readCapability] removeObject:rc];
					revoked = YES;

					break;
				}
			}

			if (revoked == NO) {
				[revoke release];

				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown capability", @"error", nil];
			}
		} else {
			if ([operation localizedCaseInsensitiveCompare:@"write"] == NSOrderedSame) {
				if ([rn writeCapability] == nil) {
					[revoke release];
					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown capability", @"error", nil];
				}

					// Search the name's read capabilities
				for (redisCapability *rc in [rn writeCapability]) {
					if ([[revoke capabilityToken] isEqualToNumber:[rc capabilityToken]]) {
						[[rn writeCapability] removeObject:rc];
						revoked = YES;

						break;
					}
				}

				if (revoked == NO) {
					[revoke release];

					return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unknown capability", @"error", nil];
				}
			} else {
				[revoke release];

				return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"operation unknown", @"error", nil];
			}
		}
	}
	[revoke release];

		// Now store the updated name entry in the redis store
	redisReply *reply = [self storeRedisName:rn];
	if ((reply == NULL) || (reply->type == REDIS_REPLY_ERROR)) {
		if (reply != NULL)
			freeReplyObject(reply);

		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"REDIS SET failed", @"error", nil];
	}
	freeReplyObject(reply);

	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", @"revoked", @"capability", nil];
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

#ifdef USE_REDIS
- (redisReply *)issueCommand: (NSString *)command {
	NSLog(@"Issuing: %@", command);

	redisReply *reply = redisCommand(rContext, [command UTF8String]);
	if (reply == NULL) {
		rContext = NULL;
		return NULL;
	}
	return reply;
}
#endif /* USE_REDIS */

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
	freeReplyObject(reply);

	reply = redisCommand(rContext, "DBSIZE");
	if (reply == NULL) {
		rContext = NULL;
		return;
	}
	if (reply->type == REDIS_REPLY_INTEGER)
		NSLog(@"DEBUG: Name space contains: %lld names", reply->integer);
	freeReplyObject(reply);
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

	if ((reply == NULL) || (reply->type != REDIS_REPLY_STRING)) {
		if (reply != NULL)
			freeReplyObject(reply);
		retValue = nil;
	} else {
			// NSLog(@"DEBUG: Read value: %s", reply->str);
		NSString *repString = [[NSString alloc] initWithCString:(reply->str) encoding:[NSString defaultCStringEncoding]];
		NSData *repData = [repString dataUsingEncoding:NSUTF8StringEncoding];
		[repString release];
		freeReplyObject(reply);
		
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

			NSLog(@"Command is: %@", command);

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

