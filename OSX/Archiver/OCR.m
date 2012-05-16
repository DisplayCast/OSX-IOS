// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "OCR.h"

@implementation OCR
@synthesize width = _width;
@synthesize height = _height;
@synthesize data = _data;
@synthesize isDone = _isDone;
@synthesize outputPath = _outputPath;
@synthesize timeStart = _timeStart;

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

@end
