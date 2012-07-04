// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "Faunus.h"
#import "Wallet.h"
#import "Capabilities.h"

#include "faunusGlobals.h"

@implementation Faunus
NSString *const kFaunusdServerandPort = @"127.0.0.1:9999";
NSString *const kWhiteBoardServerandPort = @"127.0.0.1:8888";

Wallet *personalWallet;

/*!
 @method: init

*/
- (id) init {
	self = [super init];

	personalWallet = [[Wallet alloc] _initWithPersonalWallet];
	NSParameterAssert(personalWallet);

	return self;
}

/*!
 Escape special characters in URL's
*/

- (NSString *)urlEncode:(NSString *)yourString {
	return ((NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)yourString, NULL, NULL, kCFStringEncodingUTF8)));
}

/*!

 Send the URL request to the faunusd server

*/
- (NSMutableDictionary *)faunusRequest:(NSString *)cmdString {
	NSString *urlString = [self urlEncode:[NSString stringWithFormat:@"http://%@/%@", kFaunusdServerandPort, cmdString]];
	NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
												cachePolicy:NSURLRequestReloadIgnoringCacheData
											timeoutInterval:2];
		// Fetch the JSON response
	NSURLResponse *response;
	NSError *error;

		// Make synchronous request
	NSData *urlData = [NSURLConnection sendSynchronousRequest:urlRequest
											returningResponse:&response
														error:&error];

	if (urlData == nil) {
		NSLog(@"Faunus service request returned an error '%@", error);

		return nil;
	} else
		return ([NSJSONSerialization JSONObjectWithData:urlData options:(NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves) error:&error]);
}

/*!

 Send the URL request to the whiteboard server

 */
- (NSMutableDictionary *) whiteboardRequest:(NSString *)cmdString {
	NSString *urlString = [self urlEncode:[NSString stringWithFormat:@"http://%@/%@", kWhiteBoardServerandPort, cmdString]];
	NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
												cachePolicy:NSURLRequestReloadIgnoringCacheData
											timeoutInterval:2];
		// Fetch the JSON response
	NSURLResponse *response;
	NSError *error;

		// Make synchronous request
	NSData *urlData = [NSURLConnection sendSynchronousRequest:urlRequest
											returningResponse:&response
														error:&error];

	if (urlData == nil) {
		NSLog(@"Whiteboard service request returned an error '%@", error);

		return nil;
	}

	return ([NSJSONSerialization JSONObjectWithData:urlData options:(NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves) error:&error]);
}

- (NSString *)createName:(NSString *)type publicP:(BOOL)public {
	NSDictionary *dict = [self faunusRequest:@"CREATENAME"];
	if (dict == nil)	// Fauns server is inaccessible
		return nil;

	NSNumber *status = [dict objectForKey:@"status"];

	switch ([status intValue]) {
		case faunusSUCCESS: {
			NSString *nm = [dict objectForKey:@"nm"];

				// Add the read capability and write capability to my wallet
			Capabilities *rc = [[Capabilities alloc] init];
			Capabilities *wc = [[Capabilities alloc] init];

			[rc setCapability:[dict objectForKey:@"readCapability"]];
			[rc setKey:nil];
			[rc setNm:nm];
			[rc setOperation:FAUNUS_READ];
			[personalWallet addCapabilities:[NSArray arrayWithObject:rc] forName:nm];

			[wc setCapability:[dict objectForKey:@"writeCapability"]];
			[wc setKey:nil];
			[wc setNm:nm];
			[wc setOperation:FAUNUS_WRITE];
			[personalWallet addCapabilities:[NSArray arrayWithObject:wc] forName:nm];

				// Add the new name to my postit note
			[self rememberName:nm forType:type];

				// If public, announce this name in the whiteboard
			if (public == YES)
				[self registerName:nm withType:type];

			return nm;
		}
		default: {
			NSLog(@"CREATENAME failed");

			return nil;
		}
	}
}

- (BOOL) addChild:(NSString *)child forName:(NSString *)nm {
	NSMutableArray *capabilities = [self listCapabilities:nm];

	for (Capabilities *cap in capabilities) {
			// We need the read capability for the name
		if ([[cap operation] isEqualToString:@"read"])
			continue;

		if ([[cap key] length] != 0)
			continue;

		NSDictionary *dict = [self faunusRequest:[NSString stringWithFormat:@"ADDCHILD?NAME=%@&CHILD=%@&CAPABILITY=%@", nm, child, [cap capability]]];
		if (dict == nil) {
			NSLog(@"FAUNUSD server down?");

			return NO;
		}

		NSNumber *status = [dict objectForKey:@"status"];
		switch ([status intValue]) {
			case faunusSUCCESS: {
				return YES;
			}
			default: {
					// Perhaps the next capability would allow us to succeed?

				continue;
			}
		}
	}
	return NO;
}

- (NSMutableArray *)listChildren:(NSString *)nm {
	NSMutableArray *capabilities = [self listCapabilities:nm];

	for (Capabilities *cap in capabilities) {
			// We need the read capability for the name
		if ([[cap operation] isEqualToString:@"write"])
			continue;

		if ([[cap key] length] != 0)
			continue;

		NSDictionary *dict = [self faunusRequest:[NSString stringWithFormat:@"LISTCHILDREN?NAME=%@&CAPABILITY=%@", nm, [cap capability]]];
		if (dict == nil) {
			NSLog(@"FAUNUSD server down?");

			return NO;
		}

		NSNumber *status = [dict objectForKey:@"status"];
		switch ([status intValue]) {
			case faunusSUCCESS: {
				NSError *error;
				NSString *names = [dict objectForKey:@"children"];
				NSParameterAssert(names != nil);
				NSData *jsonData = [names dataUsingEncoding:NSUTF8StringEncoding];

				return [NSJSONSerialization JSONObjectWithData:jsonData options:(NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves) error:&error];
			}
			default: {
					// Perhaps the next capability would allow us to succeed?

				continue;
			}
		}
	}
	return nil;
}

- (BOOL) delChild:(NSString *)child forName:(NSString *)nm {
	NSMutableArray *capabilities = [self listCapabilities:nm];

	for (Capabilities *cap in capabilities) {
			// We need the read capability for the name
		if ([[cap operation] isEqualToString:@"read"])
			continue;

		if ([[cap key] length] != 0)
			continue;

		NSDictionary *dict = [self faunusRequest:[NSString stringWithFormat:@"DELCHILD?NAME=%@&CHILD=%@&CAPABILITY=%@", nm, child, [cap capability]]];
		if (dict == nil) {
			NSLog(@"FAUNUSD server down?");

			return NO;
		}

		NSNumber *status = [dict objectForKey:@"status"];
		switch ([status intValue]) {
			case faunusSUCCESS: {
				return YES;
			}
			default: {
					// Perhaps the next capability would allow us to succeed?

				continue;
			}
		}
	}
	return NO;
}

- (BOOL) addAttr:(NSString *)key andValue:(NSString *)value forName:(NSString *)nm {
	NSMutableArray *capabilities = [self listCapabilities:nm];

	for (Capabilities *cap in capabilities) {
			// We need the write capability for the name
		if ([[cap operation] isEqualToString:@"read"])
			continue;

		if ([[cap key] length] != 0)
			continue;

		NSDictionary *dict = [self faunusRequest:[NSString stringWithFormat:@"ADDATTR?NAME=%@&KEY=%@&VALUE=%@&CAPABILITY=%@", nm, key, value, [cap capability]]];
		if (dict == nil) {
			NSLog(@"FAUNUSD server down?");

			return NO;
		}

		NSNumber *status = [dict objectForKey:@"status"];

		switch ([status intValue]) {
			case faunusSUCCESS: {
				return YES;
			}
			default: {
					// The current capability failed. Perhaps we have another write capability that would work?
				continue;
			}
		}
	}
	return NO;
}

- (NSString *) getAttr:(NSString *)key forName:(NSString *)nm {
	NSMutableArray *capabilities = [self listCapabilities:nm];
	NSMutableArray *caps = [[NSMutableArray alloc] init];

		// First we look for the key-cap, and then for the name-cap. If key-cap is present and is denied, then name-cap will also be denied (but not the other way around)
	for (Capabilities *keyCap in capabilities) {
			// We need the read capability for the name
		if ([[keyCap operation] isEqualToString:@"write"])
			continue;

		if ([[keyCap key] isEqualToString:key]) {
			[caps addObject:keyCap];

			continue;
		}
	}

	for (Capabilities *nmCap in capabilities) {
			// We need the read capability for the name
		if ([[nmCap operation] isEqualToString:@"write"])
			continue;

		if ([[nmCap key] length] == 0) {
			[caps addObject:nmCap];

			break;
		}
	}

		// we have no capability. It is possible that the name is public
	if ([caps count] == 0) {
		Capabilities *cap = [[Capabilities alloc] init];

		[cap setNm:nm];
		[cap setKey:key];
		[cap setOperation:@"read"];	// Just for debugging purposes
		[cap setCapability:@""];	// Hoping that this was publicly accessible

		[caps addObject:cap];
	}

		// NSFastEnumerator returns objects in order. Thus, we first try key capabilities before trying name capabilities
	for (Capabilities *cap in caps) {
		NSDictionary *dict = [self faunusRequest:[NSString stringWithFormat:@"GETATTR?NAME=%@&KEY=%@&CAPABILITY=%@", nm, key, [cap capability]]];
		if (dict == nil) {
			NSLog(@"FAUNUSD server down?");

			return NO;
		}

		NSNumber *status = [dict objectForKey:@"status"];
		switch ([status intValue]) {
			case faunusSUCCESS: {
				return [dict objectForKey:@"value"];
			}
			default: {
					// Perhaps, the next capability would save the day?
				continue;
			}
		}
	}

	return nil;
}

- (BOOL) delAttr:(NSString *)key forName:(NSString *)nm {
	NSMutableArray *capabilities = [self listCapabilities:nm];
	NSMutableArray *caps = [[NSMutableArray alloc] init];

		// First we look for the key-cap, and then for the name-cap. If key-cap is present and is denied, then name-cap will also be denied (but not the other way around)
	for (Capabilities *keyCap in capabilities) {
			// We need the write capability for the name
		if ([[keyCap operation] isEqualToString:@"read"])
			continue;

		if ([[keyCap key] isEqualToString:key]) {
			[caps addObject:keyCap];

			break;
		}
	}

	for (Capabilities *nmCap in capabilities) {
			// We need the write capability for the name
		if ([[nmCap operation] isEqualToString:@"read"])
			continue;

		if ([[nmCap key] length] == 0) {
			[caps addObject:nmCap];

			break;
		}
	}

		// we have no capability. It is possible that the name is public
	if ([caps count] == 0) {
		Capabilities *cap = [[Capabilities alloc] init];

		[cap setNm:nm];
		[cap setKey:key];
		[cap setOperation:@"write"];	// Just for debugging purposes
		[cap setCapability:@""];	// Hoping that this was publicly accessible

		[caps addObject:cap];
	}

		// NSFastEnumerator returns objects in order. Thus, we first try key capabilities before trying name capabilities
	for (Capabilities *cap in caps) {
		NSDictionary *dict = [self faunusRequest:[NSString stringWithFormat:@"DELATTR?NAME=%@&KEY=%@&CAPABILITY=%@", nm, key, [cap capability]]];
		if (dict == nil) {
			NSLog(@"FAUNUSD server down?");
			return NO;
		}

		NSNumber *status = [dict objectForKey:@"status"];
		switch ([status intValue]) {
			case faunusSUCCESS: {
				return YES;
			}
			default: {
					// Perhaps, the next capability would save the day?

				continue;
			}
		}
	}
	return NO;
}

- (NSMutableArray *)listAttrs:(NSString *)nm {
	NSMutableArray *capabilities = [self listCapabilities:nm];

	for (Capabilities *cap in capabilities) {
			// We need the read capability for the name
		if ([[cap operation] isEqualToString:@"write"])
			continue;

			// The attribute key is not necessary. At some point we might change the definition of listattrs to only list attribute
			//		names for which we have read access. In that case, we'd have to expose the key-read capabilities as well.
		if ([[cap key] length] != 0)
			continue;

		NSDictionary *dict = [self faunusRequest:[NSString stringWithFormat:@"LISTATTRS?NAME=%@&CAPABILITY=%@", nm, [cap capability]]];
		if (dict == nil) {
			NSLog(@"FAUNUSD server down?");

			return NO;
		}

		NSNumber *status = [dict objectForKey:@"status"];
		switch ([status intValue]) {
			case faunusSUCCESS: {
				NSError *error;
				NSString *names = [dict objectForKey:@"keys"];
				NSParameterAssert(names != nil);
				NSData *jsonData = [names dataUsingEncoding:NSUTF8StringEncoding];

				return [NSJSONSerialization JSONObjectWithData:jsonData options:(NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves) error:&error];
			}
			default: {
					// Perhaps the next capability would allow us to succeed?

				continue;
			}
		}
	}
	return nil;
}

@end

@implementation Faunus (Wallet)

- (BOOL) mergeToWallet:(NSData *)data {
	return ([personalWallet _mergeData:data]);
}
@end

@implementation Faunus (Capabilities)
- (NSMutableArray *) listCapabilities:(NSString *)nm {
	return ([personalWallet listCapabilities:nm]);
}

- (BOOL) revokeCapability:(Capabilities *)revokeCap {
	NSMutableArray *capabilities = [self listCapabilities:[revokeCap nm]];

	NSLog(@"Even if we have no capabilities, we might still succeed?");

	for (Capabilities *cap in capabilities) {
			// We need the write capability for the name
		if ([[cap operation] isEqualToString:@"write"]) {

				// If we are only operating on name, then capability on a key attribute is not valid
			if (([revokeCap key] == nil) && ([[cap key] length] != 0))
				continue;

			NSDictionary *dict;
			if ([revokeCap key] == nil)
				dict = [self faunusRequest:[NSString stringWithFormat:@"REVOKECAPABILITY?NAME=%@&REVOKE=%@&OPERATION=%@&CAPABILITY=%@", [revokeCap nm], [revokeCap capability], [revokeCap operation], [cap capability]]];
			else
				dict = [self faunusRequest:[NSString stringWithFormat:@"REVOKECAPABILITY?NAME=%@&KEY=%@&REVOKE=%@&OPERATION=%@&CAPABILITY=%@", [revokeCap nm], [revokeCap key], [revokeCap capability], [revokeCap operation], [cap capability]]];
			if (dict == nil) {
				NSLog(@"FAUNUSD server down?");

				return NO;
			}

			NSNumber *status = [dict objectForKey:@"status"];
			switch ([status intValue]) {
				case faunusSUCCESS: {
						// Remmove this revoked capability from our wallet
					[personalWallet delCapabilities:[NSArray arrayWithObject:revokeCap] forName:[revokeCap nm]];

					return (YES);
				}
				default: {
						// Perhaps the next capability would allow us to succeed?

					continue;
				}
			}
		}
	}
	return NO;
}

- (Capabilities *)cloneCapability:(Capabilities *)cloneCap {
	NSMutableArray *capabilities = [self listCapabilities:[cloneCap nm]];

	NSLog(@"Even if we have no capabilities, we might still succeed?");

	for (Capabilities *cap in capabilities) {
			// We need the write capability for the name
		if ([[cap operation] isEqualToString:@"write"]) {

				// If we are only operating on name, then capability on a key attribute is not valid
			if ((([cloneCap key] == nil) || ([[cloneCap key] length] == 0)) && ([[cap key] length] != 0))
				continue;

			NSDictionary *dict;
			if (([cloneCap key] == nil) || ([[cloneCap key] length] == 0))
				dict = [self faunusRequest:[NSString stringWithFormat:@"MAKECAPABILITY?NAME=%@&OPERATION=%@&CAPABILITY=%@", [cloneCap nm], [cloneCap operation], [cap capability]]];
			else
				dict = [self faunusRequest:[NSString stringWithFormat:@"MAKECAPABILITY?NAME=%@&KEY=%@&OPERATION=%@&CAPABILITY=%@", [cloneCap nm], [cloneCap key], [cloneCap operation], [cap capability]]];
			if (dict == nil) {
				NSLog(@"FAUNUSD server down?");

				return nil;
			}

			NSNumber *status = [dict objectForKey:@"status"];
			switch ([status intValue]) {
				case faunusSUCCESS: {
					NSString *clonedCap = [dict objectForKey:@"capability"];
					NSParameterAssert(clonedCap != nil);

					Capabilities *retValue = [[Capabilities alloc] init];
					[retValue setNm: [cloneCap nm]];
					[retValue setOperation:[cloneCap operation]];
					[retValue setKey:[cloneCap key]];
					[retValue setCapability:clonedCap];

						// Remember this cloned capability in our wallet
					[personalWallet addCapabilities:[NSArray arrayWithObject:retValue] forName:[retValue nm]];

					return (retValue);
				}
				default: {
						// Perhaps the next capability would allow us to succeed?

					continue;
				}
			}
		}
	}
	return nil;
}
@end

@implementation Faunus (Postit)

- (BOOL) rememberName:(NSString *)nm forType:(NSString *)type {
	return [personalWallet _rememberName:nm forType:type];
}

- (NSMutableArray *)listNames:(NSString *)type {
	return [personalWallet _listNames:type];
}

- (BOOL) forgetName:(NSString *)nm forType:(NSString *)type {
	return [personalWallet _forgetName:nm forType:type];
}
@end

@implementation Faunus (WhiteBoard)
- (NSMutableArray *) browseLocal:(NSString *)type {
	NSMutableDictionary *dict = [self whiteboardRequest:[NSString stringWithFormat:@"BROWSE?TYPE=%@",type]];

	if (dict == nil)
		return nil;

	NSNumber *status = [dict objectForKey:@"status"];
	switch ([status intValue]) {
		case faunusSUCCESS: {
			NSError *error;
			NSString *names = [dict objectForKey:@"names"];
			NSParameterAssert(names != nil);

			NSData *jsonData = [names dataUsingEncoding:NSUTF8StringEncoding];
			
			return [NSJSONSerialization JSONObjectWithData:jsonData options:(NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves) error:&error];
		}
		default: {
			NSLog(@"ERROR: White board server returned: %@", dict);

			return nil;
		}
	}
}

- (BOOL) registerName:(NSString *)nm withType:(NSString *)type {
	NSMutableDictionary *dict = [self whiteboardRequest:[NSString stringWithFormat:@"REGISTER?TYPE=%@&NAME=%@",type, nm]];

	NSNumber *status = [dict objectForKey:@"status"];

	switch ([status intValue]) {
		case faunusSUCCESS: {
			NSLog(@"DEBUG: Published in white board");

			return YES;
		}
		default: {
			NSLog(@"ERROR: White board server returned: %@", dict);

			return NO;
		}
	}
}

- (BOOL) unregisterName:(NSString *)nm withType:(NSString *)type {
	NSMutableDictionary *dict = [self whiteboardRequest:[NSString stringWithFormat:@"UNREGISTER?TYPE=%@&NAME=%@",type, nm]];

	NSNumber *status = [dict objectForKey:@"status"];

	switch ([status intValue]) {
		case faunusSUCCESS: {
			NSLog(@"DEBUG: Published in white board");

			return YES;
		}
		default: {
			NSLog(@"ERROR: White board server returned: %@", dict);

			return NO;
		}
	}
}
@end
