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

#ifdef USE_REDIS
#include <hiredis/hiredis.h>

#define REDIS_SERVER "127.0.0.1"
#define REDIS_PORT 6379

redisContext *rContext;

#endif /* USE_REDIS */

@implementation NameServer

- (NSString *) createGUID {

	return [[[NSProcessInfo processInfo] globallyUniqueString] autorelease];
}

- (unsigned long long) createCapability {
	unsigned long long retValue = arc4random();

	NSParameterAssert(sizeof(unsigned long long) == 8);
	
	retValue = retValue << 32;
	retValue += arc4random();

	return retValue;
}

- (NSDictionary *) createName {
	NSString *nm = [self createGUID];
	NSNumber *rcapability = [NSNumber numberWithUnsignedLongLong:[self createCapability]];
	NSNumber *wcapability = [NSNumber numberWithUnsignedLongLong:[self createCapability]];
	NSDictionary *retValue = [[NSDictionary dictionaryWithObjectsAndKeys:nm, @"nm", rcapability, @"rCapability", wcapability, @"wCapability", nil] autorelease];

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
	
	[self saveDB];
	[self dumpDB];

		// [w release];
		// [r release];
	[nm release];
	[rcapability release];
	[wcapability release];

	return (retValue);
}
@end

@implementation NameServer (DataStorage)
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
    }
    return context;
}

- (void) dumpDB {
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

	rContext = redisConnect(REDIS_SERVER, REDIS_PORT);
	if (rContext -> err) {
		NSLog(@"ERROR: Cannot connect to redis server at %s:%d. Error is: %s", REDIS_SERVER, REDIS_PORT, rContext->errstr);
		rContext = NULL;
	}
#endif

}

- (void) saveDB {
	NSManagedObjectContext *context = managedObjectContext();
	NSError *error = nil;

	@try {
	if (![context save:&error]) {
		NSLog(@"Error while saving %@", ([error localizedDescription] != nil) ? [error localizedDescription] : @"Unknown Error");

		exit(1);
	}
	} @catch (NSException *e) {
		
	}
}
@end

@implementation NameServer (HTTPRest)
HTTPServer *server;

- (void) HTTPServer:server didMakeNewConnection:connection {
		// NSLog(@"DEBUG: didMakeNewConnection: %@", connection);
}

- (void) HTTPConnection:connection didReceiveRequest:(HTTPServerRequest *)mess {
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
		NSString *command = [[uri path] autorelease];
		NSDictionary *query = [uri queryComponents];

		NSLog(@"URL: %@ and query: %@", command, query);

		id responseObj = nil;
		
		if ([command localizedCaseInsensitiveCompare:@"/CREATENAME"] == NSOrderedSame) {
			responseObj = [self createName];
		}

		if ( ([[uri path] compare:@"/snapshot" options:NSCaseInsensitiveSearch] == NSOrderedSame) || ([[uri path] isEqualToString:@"/"])) {
			NSArray *tokens = [[uri query] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"&="]];
			unsigned long width = 0, height = 0;

		}

			// Finished processing. Now response to the query
		[uri release];
		[query release];

			// One of our methods created the correct response
		if (responseObj != nil) {
			CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 200, NULL, kCFHTTPVersion1_1); // OK
			CFHTTPMessageSetHeaderFieldValue(response, (CFStringRef)@"Content-Type", (CFStringRef) @"application/json");

			if ([method isEqual:@"GET"]) {
				NSError *error = [[NSError alloc] init];
				CFDataRef jsonData = (CFDataRef)[NSJSONSerialization dataWithJSONObject:responseObj options:NSJSONWritingPrettyPrinted error:&error];
				[error release];
				
				CFHTTPMessageSetBody(response, (CFDataRef)jsonData);
				CFRelease(jsonData);
			}
			[mess setResponse:response];
			
			CFRelease(responseObj);
			CFRelease(response);
			
			return;
		}

			// Undefined command
		CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 400, NULL, kCFHTTPVersion1_1); // Bad Request
        [mess setResponse:response];
        CFRelease(response);
        return;
	}

		// We do not support POST, DELETE etc.
    CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 405, NULL, kCFHTTPVersion1_1); // Method Not Allowed
    [mess setResponse:response];
    CFRelease(response);
}

- (id) init {
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
		NSLog(@"Error starting HTTP server for SNAPSHOT service: %@", startError);
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

