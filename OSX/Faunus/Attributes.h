//
//  Attributes.h
//  OSX
//
//  Created by Surendar Chandra on 6/11/12.
//  Copyright (c) 2012 FX Palo Alto Lab. Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "Name.h"

@class Capability;

@interface Attributes : Name

@property (nonatomic, retain) NSString * key;
@property (nonatomic, retain) NSString * value;
@property (nonatomic, retain) NSSet *readAttrCapability;
@property (nonatomic, retain) NSSet *writeAttrCapability;
@end

@interface Attributes (CoreDataGeneratedAccessors)

- (void)addReadAttrCapabilityObject:(Capability *)value;
- (void)removeReadAttrCapabilityObject:(Capability *)value;
- (void)addReadAttrCapability:(NSSet *)values;
- (void)removeReadAttrCapability:(NSSet *)values;

- (void)addWriteAttrCapabilityObject:(Capability *)value;
- (void)removeWriteAttrCapabilityObject:(Capability *)value;
- (void)addWriteAttrCapability:(NSSet *)values;
- (void)removeWriteAttrCapability:(NSSet *)values;

@end
