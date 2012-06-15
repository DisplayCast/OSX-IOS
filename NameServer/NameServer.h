//
//  NameServer.h
//  NameServer
//
//  Created by Surendar Chandra on 6/8/12.
//  Copyright (c) 2012 FX Palo Alto Laboratory Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NameServer: NSObject
- (NSMutableDictionary *) createName;
- (NSMutableDictionary *) addAttr: forName:(NSString *)name withKey:(NSString *)key andValue:(NSString *)value withWriteCapability:(NSString *)capability;
@end

@interface NameServer (DataStorage)
- (void) saveDB;
- (void) openDB;
- (void) dumpDB;

static NSManagedObjectModel *managedObjectModel();
static NSManagedObjectContext *managedObjectContext();
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