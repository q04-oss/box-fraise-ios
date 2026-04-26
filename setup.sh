#!/bin/bash
# Generates BoxFraise.xcodeproj from project.yml using XcodeGen.
# Run once after cloning on a Mac.

set -e

if ! command -v xcodegen &> /dev/null; then
  echo "Installing XcodeGen..."
  brew install xcodegen
fi

echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Done. Open BoxFraise.xcodeproj in Xcode."
echo "Before building, set your DEVELOPMENT_TEAM in project.yml or directly in Xcode."
