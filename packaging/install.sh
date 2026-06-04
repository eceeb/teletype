#!/bin/bash
# Builds Teletype in release and installs it as a .app bundle.
# SwiftPM only emits a bare executable, so we assemble the bundle by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building release…"
swift build -c release --product Teletype

STAGE="$(mktemp -d)/Teletype.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

# Executable (renamed to the app's name) + every SwiftPM resource bundle
# (fonts, SwiftTerm) so Bundle.module resolves them via Bundle.main.resourceURL.
cp .build/release/Teletype "$STAGE/Contents/MacOS/Teletype"
cp -R .build/release/*.bundle "$STAGE/Contents/Resources/"
cp packaging/Info.plist "$STAGE/Contents/Info.plist"
cp packaging/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

# Install to /Applications, falling back to ~/Applications if not writable.
DEST="/Applications/Teletype.app"
rm -rf "$DEST" 2>/dev/null || true
if ! cp -R "$STAGE" /Applications/ 2>/dev/null; then
	DEST="$HOME/Applications/Teletype.app"
	mkdir -p "$HOME/Applications"
	rm -rf "$DEST"
	cp -R "$STAGE" "$HOME/Applications/"
fi

# Ad-hoc sign so macOS launches it without download-quarantine friction.
codesign --force --sign - "$DEST" 2>/dev/null || true

echo "Installed → $DEST"
