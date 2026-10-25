#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

APP_NAME="AIFatigueTracker"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
BUILD_TOOLS_DIR="$PROJECT_DIR/.build_tools"

mkdir -p "$BUILD_TOOLS_DIR"
touch "$BUILD_TOOLS_DIR/empty.modulemap"

cat << EOF > "$BUILD_TOOLS_DIR/vfs.yaml"
{
  'version': 0,
  'case-sensitive': 'false',
  'roots': [
    {
      'type': 'file',
      'name': '/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap',
      'external-contents': '$BUILD_TOOLS_DIR/empty.modulemap'
    }
  ]
}
EOF

echo "🔨 Building $APP_NAME..."

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Collect all Swift source files
SWIFT_FILES=$(find "$PROJECT_DIR/Sources" -name "*.swift")

# Compile
swiftc \
    -vfsoverlay "$BUILD_TOOLS_DIR/vfs.yaml" \
    -parse-as-library \
    -target arm64-apple-macos14.0 \
    -O \
    $SWIFT_FILES \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Ad-hoc codesign with stable designated requirement for TCC
codesign --force --deep -s - -r='designated => identifier "com.dxdlab.AIFatigueTracker"' "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Build successful: $APP_BUNDLE"
