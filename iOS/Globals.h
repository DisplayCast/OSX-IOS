// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

	// Choose between local domain and wide area bonjour
	// #define     BONJOUR_DOMAIN      @"bonjour.fxpal.net."
#define     BONJOUR_DOMAIN      @""

	// Bonjour services used by DisplayCast
#define     STREAMER    @"_dc-streamer._tcp."
#define     PLAYER      @"_dc-player._tcp."
#define     ARCHIVER    @"_dc-archiver._tcp."

#define     VERSION	1.0

// PlayerIOS related variables
#undef  PLAYERIOS_USE_REMOTE_CONTROL
#define PLAYERIOS_USE_STREAMERICON
#define PLAYERIOS_ICON_SIZE     128
#undef  PLAYERIOS_USE_STATUSBAR
