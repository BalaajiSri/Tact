#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:-$PWD/build/MenubarTimer.app}"
cache="$(dirname "$app")/.swift-module-cache"
mkdir -p "$(dirname "$app")" "$cache"
staging=$(mktemp -d /tmp/menubar-timer-build.XXXXXXXX)
trap 'rm -r "$staging"' EXIT
bundle="$staging/MenubarTimer.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
sdk=$(xcrun --show-sdk-path)
swift_args=(-sdk "$sdk" -module-cache-path "$cache")

# Some Command Line Tools installations ship two maps for SwiftBridging.
maps="/Library/Developer/CommandLineTools/usr/include/swift"
if [[ "$sdk" == /Library/Developer/CommandLineTools/* ]] &&
   [[ -f "$maps/bridging.modulemap" && -f "$maps/module.modulemap" ]] &&
   diff -q <(sed -n '/^module SwiftBridging/,$p' "$maps/bridging.modulemap") \
           <(sed -n '/^module SwiftBridging/,$p' "$maps/module.modulemap") >/dev/null; then
    overlay="$staging"
    touch "$overlay/empty.modulemap"
    cat > "$overlay/maps.json" <<MAP
{"version":0,"roots":[{"type":"file","name":"$maps/module.modulemap","external-contents":"$overlay/empty.modulemap"}]}
MAP
    swift_args+=(-Xfrontend -vfsoverlay -Xfrontend "$overlay/maps.json"
                 -Xcc -ivfsoverlay -Xcc "$overlay/maps.json")
fi

swiftc "${swift_args[@]}" -O main.swift Presets.swift TimerStatusContent.swift Tracker.swift Palettes.swift ProgressCard.swift TrackerDashboard.swift TrackerEditor.swift Reminders.swift -o "$bundle/Contents/MacOS/MenubarTimer"
cp Info.plist "$bundle/Contents/Info.plist"
cp AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
ditto --noextattr "$bundle" "$app"
