//
//  faunusGlobals.h
//  OSX
//
//  Created by Surendar Chandra on 6/28/12.
//  Copyright (c) 2012 FX Palo Alto Lab. Inc. All rights reserved.
//

#ifndef OSX_faunusGlobals_h
#define OSX_faunusGlobals_h

typedef enum {
	faunusSUCCESS = 0,
	faunusEGAIN = -1,			// Couldn't complete the command now
	faunusFAILED = -2,
	faunusENOACCESS = -3,
} faunusStatus;

#define FAUNUS_READ		@"read"
#define FAUNUS_WRITE	@"write"

#endif
