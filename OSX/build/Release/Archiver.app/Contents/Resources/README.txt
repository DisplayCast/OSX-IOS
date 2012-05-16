Copyright (c) 2012, Fuji Xerox Co., Ltd.
All rights reserved.
Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.
Contact: displaycast@fxpal.com

0.0  License: 
   DisplayCast is released under the New BSD license. Specific
   licensing terms are described in the License.rtf file. This license
   agreement applies to the entire DisplayCast system.

1.0 Introduction:
    Screen sharing is an important collaboration feature. As a
    screencast, it is used to capture and archive screen contents for
    educational and training purposes. Real time screen sharing is
    widely used for remote logging, debugging and screen sharing. Some
    of the popular screen sharing applications include VNC (and
    variants such as Apple Remote Desktop), Microsoft Remote Desktop,
    Google Chrome Desktop and Cisco WebEx.

    Historically, real time screen sharing systems were designed to
    operate over constrained networks. This design choice does not
    lend itself to scenarios in which such bottlenecks are
    irrelevant. DisplayCast targets intranet scenarios in which the
    wired/wireless networks and computation resources are abundant. We
    envision a collaboration scenario in which many users share their
    screens with many other users in an intranet setting. Our primary
    design goal is to faithfully reproduce the screen contents.

    Users are not required to reconfigure their systems (e.g., lower
    screen resolution) in order to make them suitable for screen
    sharing. Users can use any application and expect good
    performance. We achieve many of these goals. Some remain
    unachievable because of processor limitations. For example,
    capturing, compressing and sharing full screen HD movies remain
    beyond reach even with the state of the art laptop
    processors. DisplayCast system currently includes three
    components: Streamer, Player and Archiver. 
    
    a) Streamer: The streamer is the source component. It can either
    share the entire screen or a portion (using a configuration MASK
    region). It interacts with users using a task-bar interface (a
    windowed interface can be compiled using appropriate compile time
    flags specified in Globals.h). Streamers are available for Windows
    7 and Mac OSX 10.6+.

    b) Player: The player is the real time receiver. The created
    windows can be dragged around using the GUI. It can also be
    remotely controlled. Players are available for Windows 7, Mac OSX
    10.6+ and iOS 5.0.

    c) Archiver: This component captures a stream into a H.264
    movie. Archiver requires OSX Mac 10.7+. 

    We also provide a HTTP/REST service that runs under Windows
    7. This service listens to the various Zeroconf advertisements and
    provides a synchronous means of controlling DisplayCast.

2.0 System Requirements:
    In Windows 7, DisplayCast requires:
    	a) Apple Bonjour for naming and location management. Either
    the full SDK or the "Bonjour Print Services for Windows", both
    available at https://developer.apple.com/opensource/ will work.
    	b) Demoforge mirror driver, available at
    http://www.demoforge.com/dfmirage.htm.

3.0 Getting DisplayCast:
    3.1 Prebuilt binaries are available from the project web page at
    http://www.fxpal.com/?p=DisplayCast/.

    3.2 Source code is available in github at
    https://github.com/DisplayCast

4.0 Build Intructions:
    4.1: Windows 7:
    We use Microsoft Visual Studio 2010. Visual Studio 2010 Express
    may also be used though the Express version does not support
    installer creation functionality.

    The source code for the various projects are available inside the
    "Sources" folder. Projects "Player" and "Streamer" create the
    corresponding DisplayCast executables. The project "Location" is
    an experimental feature that uses Cisco WiFi
    localization. "ControllerService" is a Windows service that
    listens to Bonjour services and provides a HTTP/REST service. By
    default, the service uses port 11223 and provides JSONP
    responses. "Shared" defines global parameters that are used by the
    entire system. "ZeroconfService" is the open source C# wrapper for
    Bonjour and is available at
    http://code.google.com/p/zeroconfignetservices/. You can download
    precompiled DLL from that link though I experienced some trouble
    in using the precompiled binaries.

    Installers can be built using the projects inside the Installers
    director. The projects "ControllerServiceInstaller" and
    "DisplayCastInstaller" create installers for the Controller
    Service and the DisplayCast system respectively.

    4.2: Mac OSX and iOS:
    We use Xcode 4.x. The license agreement, this README file and
    credits are available in the Documentation group. The source code
    for the OSX version of Streamer, Archiver, Players and Preferences
    are available in the Sources/OSX group. The source code for the
    iOS player is available in Sources/iOS. The global configuration
    file is available in the Sources/Shared group. An experimental
    feature that uses XMPP uses the xmppframework available in
    Sources/OSX/Extras/xmppframework. We downloaded the version that
    was available at
    https://code.google.com/p/xmppframework/. Recently, xmppframework
    is hosted at GitHub.

    With the Xcode 4.x and Command Line tools addition, the system can
    be compiled and a disk image containing the release packages can
    be created by running the shell script Packager/pkmaker.sh from
    the command line.

5.0 Known Issues:
    5.1: Windows 7

    5.2: Mac OSX

6.0 Frequently asked questions:
