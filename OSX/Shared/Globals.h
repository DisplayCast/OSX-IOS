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

#define     PREFERENCES_APPSCRIPT @"tell application \"System Preferences\"\nactivate\nset current pane to pane \"com.fxpal.displaycast.DisplayCast\"\nend tell"

#define     VERSION	1.0

#define  USE_BLUETOOTH        // Used to work and then it stopped working (in more recent SDK). Will hang in [IOBluetoothHostController defaultController]. WTF 
#undef  USE_MULTICAST
#undef  USE_XMPP

	// Streamer releated variables
// Z_BEST_SPEED, Z_BEST_COMPRESSION, Z_NO_COMPRESSION, Z_DEFAULT_COMPRESSION
#define STREAMER_ZLIB_COMPRESSION	Z_BEST_SPEED
#define STREAMER_ADVERTISE_EXTERNAL_IP

// Player related variables
#define PLAYER_USE_XIB			// Use windows created by the XIB or programmatically
#define PLAYER_TASKBAR			// Task bar style (as opposed to a windowed chooser)
#undef  PLAYER_LION_FS			// Full screen mode support in Lion or higher (10.7+)
#define PLAYER_USE_STREAMERICON
#define PLAYER_ICON_SIZE     64

#define PlayerCommandSuccess @"SUCCESS";
#define PlayerCommandUnknownError @"FATAL: Unknown command";
#define PlayerCommandStreamerNotFound @"STREAMER NOT FOUND";
#define PlayerCommandTooManySessions @"FATAL: Too many sessions";

#define PlayerCommandSyntaxErrorShow @"ERROR: SHOW <streamer>";
#define PlayerCommandSyntaxErrorClose @"ERROR: CLOSE <session>";
#define PlayerCommandSyntaxErrorIcon @"ERROR: ICON <session>";
#define PlayerCommandSyntaxErrorDico @"ERROR: DICO <session>";
#define PlayerCommandSyntaxErrorMove @"ERROR: MOVE: <session> xxy wxh";

#undef OCR

#ifdef OCR
#define ARCHIVER_TESSERACT_OCR
#undef ARCHIVER_MS_XCLOUD_OCR
#endif /* OCR */

// We are ambitious!!
#define ARCHIVER_FPS		60