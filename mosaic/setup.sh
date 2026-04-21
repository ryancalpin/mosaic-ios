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

# Generate Xcode project
echo "🏗  Generating Xcode project..."
xcodegen generate

echo ""
echo "✅ Done! Next steps:"
echo "   1. Open Mosaic.xcodeproj in Xcode"
echo "   2. Set your Development Team in project settings"
echo "   3. Let Xcode resolve Swift Package dependencies (it will do this automatically)"
echo "   4. Open CLAUDE.md and start building with Claude Code"
echo ""
echo "   Or just run: open Mosaic.xcodeproj"
