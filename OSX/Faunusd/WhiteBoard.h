// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>
#import "NameServer.h"

@interface WhiteBoard : NSObject
- (id) initWithNameServer: (NameServer *) nserver;

- (NSDictionary *) browseLocal:(NSString *)type;
- (NSDictionary *) registerName:(NSString *)nm withType:(NSString *)type;
- (NSDictionary *) unregisterName:(NSString *)nm withType:(NSString *)type;
@end

@interface WhiteBoard (HTTPRest)
- (void) HTTPConnection:connection didReceiveRequest:request;
- (void) HTTPServer:server didMakeNewConnection:connection;

- (void) start;
@end