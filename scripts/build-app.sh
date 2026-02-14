#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="EchoNotes"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release

echo "📦 Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$(swift build -c release --show-bin-path)/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Resources/"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

echo "✅ Built $APP_BUNDLE"
echo "   Drag to /Applications to install, or run: open $APP_BUNDLE"
