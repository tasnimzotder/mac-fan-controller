#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./tools/build-app.sh
version=$(cat VERSION)
stage=$(mktemp -d /tmp/mac-fan-controller-dmg.XXXXXX)
trap 'rm -rf "$stage"' EXIT
cp -R 'dist/Mac Fan Controller.app' "$stage/"
ln -s /Applications "$stage/Applications"
dmg="dist/MacFanController_v${version}_aarch64.dmg"
hdiutil create -volname 'Mac Fan Controller' -srcfolder "$stage" -ov -format UDZO "$dmg"
hdiutil verify "$dmg"
shasum -a 256 "$dmg"
