// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>

#import "Capabilities.h"

@interface Faunus : NSObject

	// #define FAUNUSD			@"127.0.0.1:9999"
	// #define WHITEBOARD		@"127.0.0.1:8888"

- (NSString *)createName:(NSString *)type publicP:(BOOL)public;

- (BOOL) addChild:(NSString *)child forName:(NSString *)nm;
- (NSMutableArray *)listChildren:(NSString *)nm;
- (BOOL) delChild:(NSString *)child forName:(NSString *)nm;

- (BOOL) addAttr:(NSString *)key andValue:(NSString *)value forName:(NSString *)nm;
- (NSString *) getAttr:(NSString *)key forName:(NSString *)nm;
- (BOOL) delAttr:(NSString *)key forName:(NSString *)nm;
- (NSMutableArray *)listAttrs:(NSString *)nm;
@end

@interface Faunus (Wallet)
- (BOOL) mergeToWallet:(NSData *)data;
@end

@interface Faunus (Capabilities)
- (NSMutableArray *) listCapabilities:(NSString *)nm;

- (BOOL) revokeCapability:(Capabilities *)cap;
- (Capabilities *)cloneCapability:(Capabilities *)cap;
@end

@interface Faunus (Postit)
- (BOOL) rememberName:(NSString *)nm forType:(NSString *)type;
- (NSMutableArray *)listNames:(NSString *)type;
- (BOOL) forgetName:(NSString *)nm forType:(NSString *)type;
@end

@interface Faunus (WhiteBoard)
- (NSMutableArray *) browseLocal:(NSString *)type;
- (BOOL) registerName:(NSString *)nm withType:(NSString *)type;
- (BOOL) unregisterName:(NSString *)nm withType:(NSString *)type;
@end

