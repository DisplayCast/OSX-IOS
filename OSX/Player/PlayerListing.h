// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import <Foundation/Foundation.h>

@interface PlayerListing : NSObject {
    @public
        NSString* _name;
        NSNetService* _ns;
    @private
}

@property (nonatomic, retain, readwrite ) NSNetService *ns;
@property (nonatomic, retain, readwrite ) NSString *name;
@end
