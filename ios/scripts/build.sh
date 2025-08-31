#!/bin/bash

# =============================================================================
# VibeTunnel iOS Build Script
# =============================================================================
# 
# This script builds the VibeTunnel iOS application using xcodebuild with
# support for both simulator and device builds.
#
# USAGE:
#   ./scripts/build.sh [--configuration Debug|Release] [--simulator|--device]
#
# ARGUMENTS:
#   --configuration <Debug|Release>  Build configuration (default: Release)
#   --simulator                      Build for iOS simulator
#   --device                         Build for iOS device (default)
#
# ENVIRONMENT VARIABLES:
#   USE_WORKSPACE=YES|NO            Use workspace instead of project (default: NO)
#
# OUTPUTS:
#   - Built app at DerivedData location
#   - Version and build number information
#
# DEPENDENCIES:
#   - Xcode and command line tools
#   - xcbeautify (optional, for prettier output)
#
# EXAMPLES:
#   ./scripts/build.sh                           # Release build for device
#   ./scripts/build.sh --configuration Debug     # Debug build for device
#   ./scripts/build.sh --simulator               # Release build for simulator
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$IOS_DIR")"

# Default values
CONFIGURATION="Release"
DESTINATION="generic/platform=iOS"
USE_WORKSPACE="${USE_WORKSPACE:-NO}"

# Determine project/workspace
if [[ "$USE_WORKSPACE" == "YES" ]] && [[ -f "$IOS_DIR/VibeTunnel-iOS.xcodeproj/project.xcworkspace/contents.xcworkspacedata" ]]; then
    PROJECT_FILE="$IOS_DIR/VibeTunnel-iOS.xcodeproj/project.xcworkspace"
    PROJECT_ARG="-workspace"
    echo "Using workspace: $PROJECT_FILE"
elif [[ -f "$IOS_DIR/VibeTunnel-iOS.xcodeproj/project.pbxproj" ]]; then
    PROJECT_FILE="$IOS_DIR/VibeTunnel-iOS.xcodeproj"
    PROJECT_ARG="-project"
    echo "Using project: $PROJECT_FILE"
else
    echo "Error: No Xcode project or workspace found"
    exit 1
fi

SCHEME="VibeTunnel-iOS"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        --simulator)
            DESTINATION="platform=iOS Simulator,name=iPhone 15"
            shift
            ;;
        --device)
            DESTINATION="generic/platform=iOS"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--configuration Debug|Release] [--simulator|--device]"
            exit 1
            ;;
    esac
done

echo "Building VibeTunnel iOS..."
echo "Configuration: $CONFIGURATION"
echo "Destination: $DESTINATION"

# Change to iOS directory
cd "$IOS_DIR"

# Build the app
echo "🔨 Building iOS app..."

# Check if xcbeautify is available
if command -v xcbeautify &> /dev/null; then
    echo "Building with xcbeautify for cleaner output..."
    xcodebuild build \
        $PROJECT_ARG "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "$DESTINATION" | xcbeautify
else
    echo "Building (install xcbeautify for cleaner output)..."
    xcodebuild build \
        $PROJECT_ARG "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "$DESTINATION"
fi

# Check if build succeeded by looking for exit code
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✓ Build completed successfully"
else
    echo "✗ Build failed"
    exit 1
fi

# Try to find and display the built app info
echo ""
echo "Build Details:"
echo "- Configuration: $CONFIGURATION"
echo "- Scheme: $SCHEME"
echo "- Destination: $DESTINATION"

# Get build settings to find the app location
BUILT_PRODUCTS_DIR=$(xcodebuild $PROJECT_ARG "$PROJECT_FILE" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings | grep "BUILT_PRODUCTS_DIR" | head -n 1 | awk '{print $3}')

if [[ -n "$BUILT_PRODUCTS_DIR" ]] && [[ -d "$BUILT_PRODUCTS_DIR" ]]; then
    APP_PATH="$BUILT_PRODUCTS_DIR/VibeTunnel.app"
    if [[ -d "$APP_PATH" ]]; then
        echo "- App location: $APP_PATH"
        
        # Try to get version info
        if [[ -f "$APP_PATH/Info.plist" ]]; then
            VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Info.plist" 2>/dev/null || echo "Unknown")
            BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Info.plist" 2>/dev/null || echo "Unknown")
            echo "- Version: $VERSION ($BUILD)"
        fi
    else
        echo "- App bundle not found at expected location"
    fi
else
    echo "- Could not determine app location"
fi

echo ""
echo "Build complete! 🎉"