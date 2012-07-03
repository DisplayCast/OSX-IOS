// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>

#include <sqlite3.h>
#include <sys/stat.h>

@interface Wallet : NSObject /* <NSCoding> */ {
	sqlite3 *db;
	BOOL memoryDB;
}

- (BOOL)addCapabilities:(NSArray *)capabilities forName:(NSString *)nm;
- (BOOL)delCapabilities:(NSArray *)capabilities forName:(NSString *)nm;
- (NSMutableArray *) listCapabilities:(NSString *)nm;

- (NSData *) getData;				// converts the wallet into NSData for shipping to remote site

- (id) _initWithPersonalWallet;		// Used internally to create our personal wallet. init creates a temporary wallet
- (BOOL) _mergeData:(NSData *)data; // Merge data into the current wallet
@end

@interface Wallet (Postit)
- (BOOL) _rememberName:(NSString *)nm forType:(NSString *)type;
- (NSMutableArray *)_listNames:(NSString *)type;
- (BOOL) _forgetName:(NSString *)nm forType:(NSString *)type;
@end
