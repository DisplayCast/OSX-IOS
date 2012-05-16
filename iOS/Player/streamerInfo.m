//
//  streamerInfo.m
//  DisplayCast
//
//  Created by Surendar Chandra on 5/8/12.
//  Copyright (c) 2012 FX Palo Alto Lab. Inc. All rights reserved.
//

#import "streamerInfo.h"

@implementation streamerInfo
@synthesize name;
@synthesize icon;
@synthesize imageURLString;

- (void)dealloc {
    [name release];
    [icon release];
    [imageURLString release];
    
    [super dealloc];
}
@end
