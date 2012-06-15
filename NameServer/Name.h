//
//  Name.h
//  NameServer
//
//  Created by Surendar Chandra on 6/8/12.
//  Copyright (c) 2012 FX Palo Alto Laboratory Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Attributes, Capability, Children;

@interface Name : NSManagedObject

@property (nonatomic, retain) NSString * id;
@property (nonatomic, retain) NSSet *attributes;
@property (nonatomic, retain) Children *children;
@property (nonatomic, retain) NSSet *readCapability;
@property (nonatomic, retain) NSSet *writeCapability;
@end

@interface Name (CoreDataGeneratedAccessors)

- (void)addAttributesObject:(Attributes *)value;
- (void)removeAttributesObject:(Attributes *)value;
- (void)addAttributes:(NSSet *)values;
- (void)removeAttributes:(NSSet *)values;

- (void)addReadCapabilityObject:(Capability *)value;
- (void)removeReadCapabilityObject:(Capability *)value;
- (void)addReadCapability:(NSSet *)values;
- (void)removeReadCapability:(NSSet *)values;

- (void)addWriteCapabilityObject:(Capability *)value;
- (void)removeWriteCapabilityObject:(Capability *)value;
- (void)addWriteCapability:(NSSet *)values;
- (void)removeWriteCapability:(NSSet *)values;

@end
