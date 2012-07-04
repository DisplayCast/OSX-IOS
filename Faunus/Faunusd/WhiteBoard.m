// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "WhiteBoard.h"
#import "HTTPServer.h"

@implementation WhiteBoard
HTTPServer *server;
NameServer *nm;


- (id) initWithNameServer: (NameServer *) nserver {
	self = [super init];

	nm = nserver;

	[nm openDB];

	server = [[HTTPServer alloc] init];
	[server setPort:8888];

	return self;
}

/*!

 @method: browseLocal
 @param: type

 */
- (NSDictionary *) browseLocal:(NSString *)type {
	[nm openDB];

#ifdef USE_REDIS
	redisReply *reply = [nm issueCommand:[NSString stringWithFormat:@"SMEMBERS \"%@\"", type]];

	if ((reply == NULL) || (reply->type != REDIS_REPLY_ARRAY)) {
		if (reply != NULL)
			freeReplyObject(reply);

		return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"redis error", @"error", nil];
	}

	NSMutableArray *nms = [[[NSMutableArray alloc] init] autorelease];
	for (size_t i = 0; i < reply->elements; i++)
		[nms addObject:[NSString stringWithFormat:@"%s", reply->element[i]->str]];

		// Now create a JSON response of the keys
	NSError *error = nil;
	NSData *json = [NSJSONSerialization dataWithJSONObject:nms options:0 error:&error];
	NSString *jsonStr = [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease];

	freeReplyObject(reply);

	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", jsonStr, @"names", nil];
#endif /* USE_REDIS */

	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

/*!

 @method: registerName
 @param: name
 @param: type

 */
- (NSDictionary *) registerName:(NSString *)name withType:(NSString *)type {
	[nm openDB];

#ifdef USE_REDIS
	redisReply *reply = [nm issueCommand:[NSString stringWithFormat:@"SADD \"%@\" %@", type, name]];
	if (reply != NULL)
		freeReplyObject(reply);

	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];
#endif /* USE_REDIS */

	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}

/*!

 @method: unregisterName
 @param: name
 @param: type

 */
- (NSDictionary *) unregisterName:(NSString *)name withType:(NSString *)type {
	[nm openDB];

#ifdef USE_REDIS
	redisReply *reply = [nm issueCommand:[NSString stringWithFormat:@"SREM \"%@\" %@", type, name]];
	NSDictionary *retValue;
	if (reply && (reply->type == REDIS_REPLY_ERROR))
		retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"Name not registered", @"error", nil];
	else
		retValue = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusSUCCESS], @"status", nil];

	if (reply != NULL)
		freeReplyObject(reply);

	return retValue;
#endif /* USE_REDIS */

	return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:faunusFAILED], @"status", @"unimplemented function", @"error", nil];
}
@end

@implementation WhiteBoard (HTTPRest)
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

			if ([command localizedCaseInsensitiveCompare:@"/BROWSE"] == NSOrderedSame) {
				NSArray *type = [query objectForKey:@"TYPE"];
				if (type != nil)
					responseObj = [self browseLocal:[type objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/REGISTER"] == NSOrderedSame) {
				NSArray *type = [query objectForKey:@"TYPE"];
				NSArray *name = [query objectForKey:@"NAME"];

				if ((name != nil) && (type != nil))
					responseObj = [self registerName:[name objectAtIndex:0] withType:[type objectAtIndex:0]];
			} else if ([command localizedCaseInsensitiveCompare:@"/UNREGISTER"] == NSOrderedSame) {
				NSArray *type = [query objectForKey:@"TYPE"];
				NSArray *name = [query objectForKey:@"NAME"];

				if ((name != nil) && (type != nil))
					responseObj = [self unregisterName:[name objectAtIndex:0] withType:[type objectAtIndex:0]];
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
