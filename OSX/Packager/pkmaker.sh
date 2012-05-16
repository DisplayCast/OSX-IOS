#!/bin/sh

echo "$0: Building the project"
(cd ..; xcodebuild -target Preferences -parallelizeTargets clean build)
# sudo \rm -rf /Library/PreferencePanes/DisplayCast.prefPane/; sudo mv ../build/Release/DisplayCast.prefPane/ /Library/PreferencePanes/

(cd ..; xcodebuild -target Streamer -parallelizeTargets clean build)
(cd ..; xcodebuild -target Player -parallelizeTargets clean build)
(cd ..; xcodebuild -target Archiver -parallelizeTargets clean build)

echo "$0: Building package"
tmpdest=/tmp/Pkg; export tmpdest
mkdir -p ${tmpdest}
cp -pr EnableAutoLogin.app ${tmpdest}

[ -x /Developer/usr/bin/packagemaker ] && PKGMAKER="/Developer/usr/bin/packagemaker"
[ -x "/Applications/Developer/Auxillary Tools/PackageMaker.app/Contents/MacOS/PackageMaker" ] && PKGMAKER="/Applications/Developer/Auxillary Tools/PackageMaker.app/Contents/MacOS/PackageMaker"

[ ! -x "${PKGMAKER}" ] && echo "$0: Package maker not installed" && exit 1

(cd ..; "${PKGMAKER}" --doc PackageMaker.pmdoc -v -o DisplayCast.pkg)
mv ../DisplayCast.pkg ${tmpdest}

title="DisplayCast"; export title
size=20000; export size
rm -f pack.temp.dmg
hdiutil create -srcfolder "${tmpdest}" -volname "${title}" -fs HFS+ \
      -fsargs "-c c=64,a=16,e=16" -format UDRW -size ${size}k pack.temp.dmg

device=$(hdiutil attach -readwrite -noverify -noautoopen "pack.temp.dmg" | \
         egrep '^/dev/' | sed 1q | awk '{print $1}')

sleep 5

backgroundPictureName="FXPAL_logo.png"; export backgroundPictureName
mkdir /Volumes/${title}/.background
mkdir /Volumes/${title}/.Trashes
cp FXPAL_logo.png /Volumes/${title}/.background

echo '
   tell application "Finder"
     tell disk "'${title}'"
           open
           set current view of container window to icon view
           set toolbar visible of container window to false
           set statusbar visible of container window to false
           set the bounds of container window to {400, 100, 885, 430}
           set theViewOptions to the icon view options of container window
           # set arrangement of theViewOptions to not arranged
           set icon size of theViewOptions to 144
           set background picture of theViewOptions to file ".background:'${backgroundPictureName}'"
           update without registering applications
           delay 5
     end tell
   end tell
' | osascript

finalDMGName=DisplayCast.dmg; export finalDMGName
rm -f ${finalDMGName}

chmod -Rf go-w /Volumes/"${title}"
sync; sync
hdiutil detach ${device}
hdiutil convert "pack.temp.dmg" -format UDZO -imagekey zlib-level=9 -o "${finalDMGName}"

rm -f pack.temp.dmg 
rm -rf ${tmpdest}

mv DisplayCast.dmg ../Installers
echo "Moved DisplayCast.dmg to ../../Installers/"
