// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

@interface OCR : NSObject {
@public
    UInt32 _width, _height;
	UInt32 *_data;
	BOOL _isDone;
	NSString *_outputPath;
	NSDate *_timeStart;
@private
}

@property (nonatomic, readwrite ) UInt32 width;
@property (nonatomic, readwrite ) UInt32 height;
@property (nonatomic, readwrite ) UInt32* data;
@property (nonatomic, readwrite ) BOOL isDone;
@property (nonatomic, readwrite, retain ) NSString *outputPath;
@property (nonatomic, readwrite, retain ) NSDate *timeStart;

@end
