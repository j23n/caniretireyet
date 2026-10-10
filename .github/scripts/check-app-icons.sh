#!/bin/bash
# Checks that the built apps have their icons (ci.yml, `make check-icons`). An app without its
# icon still builds (an empty or missing ASSETCATALOG_COMPILER_APPICON_NAME, an icon set the
# platform can't use), so this looks in the built bundles: the icon's name in Info.plist, and
# its images in the compiled asset catalog (and the Mac's .icns).
#
#   check-app-icons.sh DERIVED_DATA
set -euo pipefail

products="$1/Build/Products"
mac="$products/Debug/CanIRetireYet.app/Contents"
ios="$products/Debug-iphonesimulator/CanIRetireYet.app"
echo "Mac Info.plist:"; plutil -p "$mac/Info.plist" | grep -i icon || true
echo "Mac Resources:"; ls -l "$mac/Resources"
echo "Mac Assets.car, AppIcon renditions:"
xcrun assetutil --info "$mac/Resources/Assets.car" | grep -c '"Name" : "AppIcon"' || true
echo "iOS Info.plist:"; plutil -p "$ios/Info.plist" | grep -i -A4 icon || true
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$mac/Info.plist")" = AppIcon
test -s "$mac/Resources/AppIcon.icns"
xcrun assetutil --info "$mac/Resources/Assets.car" | grep -q '"Name" : "AppIcon"'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$ios/Info.plist")" = AppIcon
