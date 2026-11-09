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

RELEASE_MODE=false
CREATE_DMG=false
EXTRA_SWIFT_FLAGS=""

for arg in "$@"; do
  case $arg in
    --release)
      RELEASE_MODE=true
      ;;
    --dmg)
      CREATE_DMG=true
      ;;
  esac
done

if [ "$RELEASE_MODE" = true ]; then
  echo "🚀 Building $APP_NAME for RELEASE (참여자 배포용: 디버그 모니터 자동 비활성화)..."
  EXTRA_SWIFT_FLAGS="-D RELEASE_BUILD"
else
  echo "🔨 Building $APP_NAME for DEVELOPMENT/PILOT (파일럿/개발용: 디버그 모니터 포함)..."
  EXTRA_SWIFT_FLAGS="-D DEBUG_BUILD"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy App Icon & Resources
if [ -d "$PROJECT_DIR/Sources/Resources" ]; then
  cp -R "$PROJECT_DIR/Sources/Resources/"* "$APP_BUNDLE/Contents/Resources/"
fi

# Snapshot Swift sources to prevent editor auto-save / mtime changes during compilation
SNAPSHOT_DIR="$BUILD_TOOLS_DIR/src_snapshot"
rm -rf "$SNAPSHOT_DIR"
mkdir -p "$SNAPSHOT_DIR"
cp -R "$PROJECT_DIR/Sources/" "$SNAPSHOT_DIR/"
SWIFT_FILES=$(find "$SNAPSHOT_DIR" -name "*.swift")

# Compile
swiftc \
    -vfsoverlay "$BUILD_TOOLS_DIR/vfs.yaml" \
    -parse-as-library \
    -target arm64-apple-macos14.0 \
    -O \
    $EXTRA_SWIFT_FLAGS \
    $SWIFT_FILES \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Ad-hoc codesign with stable designated requirement for TCC
codesign --force --deep -s - -r='designated => identifier "com.dxdlab.AIFatigueTracker"' "$APP_BUNDLE" 2>/dev/null || true

# If installed in /Applications, sync the updated build so macOS Quit & Reopen targets the latest build
if [ -d "/Applications/$APP_NAME.app" ]; then
  echo "📦 Updating /Applications/$APP_NAME.app with latest build..."
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
  codesign --force --deep -s - -r='designated => identifier "com.dxdlab.AIFatigueTracker"' "/Applications/$APP_NAME.app" 2>/dev/null || true
fi

# Refresh macOS LaunchServices registry
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true
if [ -d "/Applications/$APP_NAME.app" ]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app" 2>/dev/null || true
fi

echo "✅ Build successful: $APP_BUNDLE (and synced to /Applications/$APP_NAME.app)"

# If --dmg requested, generate Drag-and-Drop installer DMG
if [ "$CREATE_DMG" = true ]; then
  VERSION="0.1.2"
  echo "💿 Creating Drag-and-Drop installer DMG (AIFatigueTracker-Pilot-v${VERSION}.dmg)..."
  STAGING_DIR="/tmp/AIFatigueTracker_DMG_Staging"
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"
  cp -R "$APP_BUNDLE" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"
  hdiutil create -volname "AIFatigueTracker Pilot v${VERSION}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$PROJECT_DIR/AIFatigueTracker-Pilot-v${VERSION}.dmg"
  cp -f "$PROJECT_DIR/AIFatigueTracker-Pilot-v${VERSION}.dmg" "$PROJECT_DIR/AIFatigueTracker-Pilot.dmg"
  rm -rf "$STAGING_DIR"
  echo "✅ DMG created: $PROJECT_DIR/AIFatigueTracker-Pilot-v${VERSION}.dmg (and linked to AIFatigueTracker-Pilot.dmg)"
fi
