// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>
#define USE_REDIS

#ifdef USE_REDIS
#import "redisName.h"
#import "redisCapability.h"

#include <hiredis/hiredis.h>
#include "faunusGlobals.h"
#include "faunusGlobals.h"

	// By default, expire keys in 7 days - unless a child or attribute is added before this duration is up
#define REDIS_EXPIRE (3600*24*7)
#endif /* USE_REDIS */

@interface NameServer: NSObject
-(id) initWithRedisServer:(char *)server andPort:(int)port andDB:(int)db;

- (NSDictionary *) createName;
- (NSDictionary *) addAttr:(NSString *)name withKey:(NSString *)key andValue:(NSString *)value withWriteCapability:(NSString *)capability;
- (NSDictionary *) getAttr:(NSString *)name withKey:(NSString *)key withReadCapability:(NSString *)capability;
- (NSDictionary *) delAttr:(NSString *)name withKey:(NSString *)key withWriteCapability:(NSString *)capability;

- (NSDictionary *) listAttrs:(NSString *)name withReadCapability:(NSString *)capability;

- (NSDictionary *) addChild:(NSString *)name withChild:(NSString *)child withWriteCapability:(NSString *)capability;
- (NSDictionary *) delChild:(NSString *)name withChild:(NSString *)child withWriteCapability:(NSString *)capability;
- (NSDictionary *) listChildren:(NSString *)name withReadCapability:(NSString *)capability;

- (NSDictionary *)makeCapabilityWithCapability:(NSString *)name withKey:(NSString *)key forOperation:(NSString *)operation withWriteCapability:(NSString *)capability;
- (NSDictionary *)revokeCapability:(NSString *)name withKey:(NSString *)key forOperation:(NSString *)operation revokeCapability:(NSString *)revokeCapability withWriteCapability:(NSString *)capability;
@end

@interface NameServer (Utilities)
- (NSString *) createGUID;
- (BOOL) allowAccess: (NSString *)capability withPermission:(NSArray *)capabilities;

#ifdef USE_REDIS
- (redisName *) getRedisName: (NSString *)name;
- (redisReply *) storeRedisName: (redisName *)rn;
#endif /* USE_REDIS */

@end

@interface NameServer (DataStorage)
- (redisReply *)issueCommand: (NSString *)command;
- (void) saveDB;
- (void) openDB;
- (void) dumpDB;

#ifdef USE_COREDATA
static NSManagedObjectModel *managedObjectModel();
static NSManagedObjectContext *managedObjectContext();
#endif /* USE_COREDATA */
@end

@interface NameServer (HTTPRest)
- (void) HTTPConnection:connection didReceiveRequest:request;
- (void) HTTPServer:server didMakeNewConnection:connection;
	
- (void) start;
@end

@interface NSString (XQueryComponents)
- (NSString *)stringByDecodingURLFormat;
- (NSString *)stringByEncodingURLFormat;
- (NSMutableDictionary *)dictionaryFromQueryComponents;
@end

@interface NSURL (XQueryComponents)
- (NSMutableDictionary *)queryComponents;
@end

@interface NSDictionary (XQueryComponents)
- (NSString *)stringFromQueryComponents;
@end
