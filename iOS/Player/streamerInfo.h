//
//  streamerInfo.h
//  DisplayCast
//
//  Created by Surendar Chandra on 5/8/12.
//  Copyright (c) 2012 FX Palo Alto Lab. Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface streamerInfo : NSObject {
	NSString *name;
    UIImage *icon;
    NSString *imageURLString;
}

@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) UIImage *icon;
@property (nonatomic, retain) NSString *imageURLString;
@end
