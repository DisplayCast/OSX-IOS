// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "Wallet.h"
#import "Capabilities.h"

@implementation Wallet
	// sqlite3 *db = nil;
	// BOOL memoryDB = NO;

/*!
 @method:addCapabilities
 @param: Array of Capabilities structure
 @param: name

 Adds all the capabilities from the array into the current wallet. Used internall for the personal wallet as well as externally for the temporay wallet 
*/
- (BOOL)addCapabilities:(NSArray *)capabilities forName:(NSString *)nm {
	for (Capabilities *capability in capabilities) {
		NSParameterAssert([nm isEqualToString:[capability nm]]);

		char *err;
		NSString *cmd = [NSString stringWithFormat:@"INSERT INTO 'wallet' VALUES ('%@', '%@', '%@', '%@');", [capability nm], (([capability key] == nil) ? @"" : [capability key]), [capability operation], [capability capability]];

		if (sqlite3_exec(db, [cmd UTF8String], NULL, NULL, &err) != SQLITE_OK) {
			sqlite3_close(db);

			NSAssert(0, @"Failed to insert into wallet");
			return NO;
		}
	}

	return YES;
}

- (BOOL)delCapabilities:(NSArray *)capabilities forName:(NSString *)nm {
	for (Capabilities *capability in capabilities) {
		NSParameterAssert([nm isEqualToString:[capability nm]]);

		char *err;
		NSString *cmd = [NSString stringWithFormat:@"DELETE FROM 'wallet' WHERE (capability IS '%@')';", [capability capability]];

		if (sqlite3_exec(db, [cmd UTF8String], NULL, NULL, &err) != SQLITE_OK) {
			sqlite3_close(db);

			NSAssert(0, @"Failed to delete from wallet");
			return NO;
		}
	}

	return YES;
}

int listCapabilitiesCallBack(void *a, int argc, char **argv, char **colName) {
	assert(argc == 4);
	assert(strcmp(colName[0], "name") == 0);
	assert(strcmp(colName[1], "key") == 0);
	assert(strcmp(colName[2], "operation") == 0);
	assert(strcmp(colName[3], "capability") == 0);

	NSMutableArray *array = (__bridge NSMutableArray *)a;
	Capabilities *cap = [[Capabilities alloc] init];

	[cap setNm:[NSString stringWithFormat:@"%s", argv[0]]];
	[cap setKey:[NSString stringWithFormat:@"%s", argv[1]]];
	[cap setOperation:[NSString stringWithFormat:@"%s", argv[2]]];
	[cap setCapability:[NSString stringWithFormat:@"%s", argv[3]]];

	[array addObject:cap];

	return 0;
}

- (NSMutableArray *) listCapabilities:(NSString *)nm {
	char *err;
	NSString *cmd = [NSString stringWithFormat:@"SELECT * FROM 'wallet' WHERE (name IS '%@');", nm];

	NSMutableArray *array = [[NSMutableArray alloc] init];
	if (sqlite3_exec(db, [cmd UTF8String], listCapabilitiesCallBack, (__bridge void *)array, &err) != SQLITE_OK) {
		sqlite3_close(db);

		NSAssert(0, @"Failed to insert into wallet");
		return nil;
	}

	return array;
}

- (void) createTables {
		// Name:KeyAttr:Operation(Read/Write):Capability
	char *err;;
	if (sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS 'wallet' ( 'name' TEXT, 'key' TEXT, 'operation' TEXT NOT NULL, 'capability' TEXT NOT NULL);", NULL, NULL, &err) != SQLITE_OK) {
		sqlite3_close(db);
		NSAssert(0, @"Failed to create wallet");
	}

	if (sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS 'postit' ( 'name' TEXT, 'type' TEXT NOT NULL);", NULL, NULL, &err) != SQLITE_OK) {
		sqlite3_close(db);
		NSAssert(0, @"Failed to create postit note");
	}
}

- (id) _initWithPersonalWallet {
	self = [super init];

	NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *dbDir = [NSString stringWithFormat:@"%@/Faunus/", [dirs objectAtIndex:0]];
	mkdir([dbDir UTF8String], 0700);

	NSString *dbFile = [NSString stringWithFormat:@"%@/Faunus/wallet.db", [dirs objectAtIndex:0]];
	if (sqlite3_open([dbFile UTF8String], &db) != SQLITE_OK) {
		NSLog(@"FATAL: Could not create wallet at %@", dbFile);

		return nil;
	}

	[self createTables];
	memoryDB = NO;

	return self;
}

- (id) init {
	self = [super init];

	if (sqlite3_open(":memory:", &db) != SQLITE_OK) {
		NSLog(@"FATAL: Creating a in-memory sqlite3 data base failed");

		db = nil;

		return nil;
	}

	[self createTables];
	memoryDB = YES;

	return self;
}

- (BOOL) _mergeData:(NSData *)data {
	const char *tempFile = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"walletUnArchive.db"] fileSystemRepresentation];

	if ([data writeToFile:[NSString stringWithCString:tempFile encoding:NSUTF8StringEncoding] atomically:YES] == NO)
		return NO;

	char *err;
	NSString *cmd = [NSString stringWithFormat:@"ATTACH DATABASE '%@' AS toMerge;", [NSString stringWithFormat:@"%s", tempFile]];
	if (sqlite3_exec(db, [cmd UTF8String], NULL, NULL, &err) != SQLITE_OK)
		NSLog(@"FAILURE to attach");

	cmd = [NSString stringWithFormat:@"INSERT INTO main.wallet select * from toMerge.wallet;"];
	if (sqlite3_exec(db, [cmd UTF8String], NULL, NULL, &err) != SQLITE_OK)
		NSLog(@"FAILURE to insert");

	cmd = [NSString stringWithFormat:@"DETACH DATABASE toMerge;"];
	if (sqlite3_exec(db, [cmd UTF8String], NULL, NULL, &err) != SQLITE_OK)
		NSLog(@"FAILURE to detach");

/*
	sqlite3 *tmpDB;
	if (sqlite3_open(tempFile, &tmpDB) != SQLITE_OK)
		return NO;

	sqlite3_backup *pBackup = sqlite3_backup_init(db, "main", tmpDB, "main");
	if (pBackup == NULL)
		return NO;

	if (sqlite3_backup_step(pBackup, -1) != SQLITE_DONE)
		return NO;

	if (sqlite3_backup_finish(pBackup) != SQLITE_OK)
		return NO;

	sqlite3_close(tmpDB);
*/

	unlink(tempFile);

	return YES;
}

- (NSData *) getData {
	const char *tempFile = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"walletArchive.db"] fileSystemRepresentation];
	sqlite3 *tmpFile;

/*
	NSLog(@"DEBUGGING");
	char *err;
	NSString *cmd = [NSString stringWithFormat:@"INSERT INTO 'wallet' VALUES ('%@', '%@', '%@', '%@');", @"SURENDAR", @"KEY", @"OPERATION", @"CAPABILITY"];
	sqlite3_exec(db, [cmd UTF8String], NULL, NULL, &err);
*/
	
	if (sqlite3_open(tempFile, &tmpFile) != SQLITE_OK)
		return nil;

	sqlite3_backup *backup = sqlite3_backup_init(tmpFile, "main", db, "main");
	if (!backup) {
		NSLog(@"FATAL in getData: %s", sqlite3_errmsg(tmpFile));

		return nil;
	}

	sqlite3_backup_step(backup, -1);
	sqlite3_backup_finish(backup);

	sqlite3_close(tmpFile);

	NSData *retValue = [NSData dataWithContentsOfFile:[NSString stringWithCString:tempFile encoding:NSUTF8StringEncoding]];

	unlink(tempFile);

	return retValue;
}


	// NSData* myData = [NSData dataWithContentsOfFile:myFileWithPath];
	// NSUInteger len = [data length];
	// unsigned char *bytePtr = (unsigned char *)[data bytes];

	// NSCoding is not portable across platforms
#if 0
- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super init]) {
        self.title = [decoder decodeObjectForKey:@"title"];
        self.author = [decoder decodeObjectForKey:@"author"];
        self.published = [decoder decodeBoolForKey:@"published"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:title forKey:@"time"];
    [encoder encodeObject:author forKey:@"author"];
    [encoder encodeBool:published forKey:@"published"];
}
#endif /* 0 */
@end

@implementation Wallet (Postit)
- (BOOL) _rememberName:(NSString *)nm forType:(NSString *)type {
	char *err;
	NSString *cmd = [NSString stringWithFormat:@"INSERT INTO 'postit' VALUES ('%@', '%@');", nm, type];

	if (sqlite3_exec(db, [cmd UTF8String], NULL, NULL, &err) != SQLITE_OK) {
		sqlite3_close(db);

		NSAssert(0, @"Failed to insert into postit");
		return NO;
	}
	return YES;
}

int listNamesCallBack(void *a, int argc, char **argv, char **colName) {
	assert(argc == 1);
	assert(strcmp(colName[0], "name") == 0);

	NSMutableArray *array = (__bridge NSMutableArray *)a;

	[array addObject:[NSString stringWithFormat:@"%s", argv[0]]];

	return 0;
}

- (NSMutableArray *)_listNames:(NSString *)type {
	char *err;
	NSString *cmd = [NSString stringWithFormat:@"SELECT name FROM 'postit' WHERE (type IS '%@');", type];

	NSMutableArray *array = [[NSMutableArray alloc] init];
	if (sqlite3_exec(db, [cmd UTF8String], listNamesCallBack, (__bridge void *)array, &err) != SQLITE_OK) {
		sqlite3_close(db);

		NSAssert(0, @"Failed to insert into wallet");
		return nil;
	}

	return array;
	NSLog(@"Not implemented");
}

- (BOOL) _forgetName:(NSString *)nm forType:(NSString *)type {
	char *err;
	NSString *cmd = [NSString stringWithFormat:@"DELETE FROM 'postit' WHERE ((name = '%@') AND (type = '%@'));", nm, type];

	if (sqlite3_exec(db, [cmd UTF8String], NULL, NULL, &err) != SQLITE_OK) {
		sqlite3_close(db);

		NSAssert(0, @"Failed to delete from postit");
		return NO;
	}
	return YES;
}
@end