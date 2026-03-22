#!/bin/bash
# Build On Your Marks as a proper macOS .app bundle
set -euo pipefail

APP_NAME="On Your Marks"
BUNDLE_NAME="OnYourMarks"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building ${APP_NAME}..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/$BUNDLE_NAME" "$MACOS_DIR/$BUNDLE_NAME"

# Copy Info.plist
cp Info.plist "$CONTENTS_DIR/Info.plist"

# Add CFBundleExecutable and NSHighResolutionCapable to the plist
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $BUNDLE_NAME" "$CONTENTS_DIR/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $BUNDLE_NAME" "$CONTENTS_DIR/Info.plist"

/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$CONTENTS_DIR/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :NSHighResolutionCapable true" "$CONTENTS_DIR/Info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS_DIR/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$CONTENTS_DIR/Info.plist"

# Copy icon
if [ -f "Sources/Resources/AppIcon.icns" ]; then
    cp "Sources/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Copy SPM bundle resources (preview.html, CSS, JS, etc.)
RESOURCE_BUNDLE="$BUILD_DIR/${BUNDLE_NAME}_OnYourMarks.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

# Also check for resources at the alternative path
RESOURCE_BUNDLE_ALT="$BUILD_DIR/${BUNDLE_NAME}_${BUNDLE_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE_ALT" ]; then
    cp -R "$RESOURCE_BUNDLE_ALT" "$RESOURCES_DIR/"
fi

echo ""
echo "App bundle created at: $APP_DIR"
echo "To run: open \"$APP_DIR\""
echo "To install: cp -R \"$APP_DIR\" /Applications/"
