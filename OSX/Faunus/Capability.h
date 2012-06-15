//
//  Capability.h
//  OSX
//
//  Created by Surendar Chandra on 6/13/12.
//  Copyright (c) 2012 FX Palo Alto Lab. Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface Capability : NSManagedObject

@property (nonatomic, retain) NSNumber * capabilityToken;
@property (nonatomic, retain) NSNumber * parentToken;

@end
