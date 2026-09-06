#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
swift build -c release -j 4 --package-path "$PROJECT_DIR"
BINARY_DIR="$(swift build -c release --show-bin-path --package-path "$PROJECT_DIR")"
APP_DIR="$OUTPUT_DIR/Piko.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_DIR/Piko" "$APP_DIR/Contents/MacOS/Piko"
cp "$PROJECT_DIR/AppBundle/Info.plist" "$APP_DIR/Contents/Info.plist"
swift "$PROJECT_DIR/Scripts/generate-icon.swift" "$APP_DIR/Contents/Resources"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
