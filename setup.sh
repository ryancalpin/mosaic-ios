#!/bin/bash
# setup.sh — Run this once on your Mac to generate the Xcode project
# Usage: chmod +x setup.sh && ./setup.sh

set -e

echo "🔧 Setting up Mosaic..."

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "📦 Installing XcodeGen..."
    brew install xcodegen
fi

# Download JetBrains Mono font (required — used throughout the UI)
RESOURCES_DIR="Resources"
mkdir -p "$RESOURCES_DIR"

FONT_FILES=(
    "JetBrainsMono-Regular.ttf"
    "JetBrainsMono-Bold.ttf"
    "JetBrainsMono-SemiBold.ttf"
)

FONT_BASE="https://github.com/JetBrains/JetBrainsMono/raw/master/fonts/ttf"

for font in "${FONT_FILES[@]}"; do
    if [ ! -f "$RESOURCES_DIR/$font" ]; then
        echo "📥 Downloading $font..."
        curl -fsSL "$FONT_BASE/$font" -o "$RESOURCES_DIR/$font"
    fi
done

echo "✅ Fonts downloaded to Resources/"

# Generate Xcode project
echo "🏗  Generating Xcode project..."
xcodegen generate

echo ""
echo "✅ Done! Next steps:"
echo "   1. Open Mosaic.xcodeproj in Xcode"
echo "   2. Set your Development Team: Xcode → Mosaic target → Signing & Capabilities"
echo "   3. Let Xcode resolve Swift Package dependencies (automatic on first build)"
echo "   4. Build and run on a device or simulator"
echo ""
echo "   Quick open: open Mosaic.xcodeproj"
