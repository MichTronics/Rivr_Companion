#!/usr/bin/env bash
# setup.sh — initialise the Rivr Companion Flutter project.
#
# Run once after cloning, or after installing Flutter.
# Requires Flutter ≥ 3.22 on PATH.
#
# Usage:
#   cd rivr_companion
#   bash setup.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Checking Flutter..."
if ! command -v flutter &>/dev/null; then
  echo "ERROR: flutter not found on PATH."
  echo "Install from https://docs.flutter.dev/get-started/install"
  exit 1
fi
flutter --version

echo ""
echo "==> Generating platform scaffolding (android, linux, windows)..."
# --overwrite-pubspec leaves pubspec.yaml untouched; merges platform dirs only.
flutter create \
  --platforms=android,linux,windows \
  --project-name=rivr_companion \
  --org=io.rivr \
  .

echo ""
echo "==> Fetching dependencies..."
flutter pub get

echo ""
echo "==> Setup complete!"
echo ""
echo "Run targets:"
echo "  Android:  flutter run -d <device>"
echo "  Linux:    flutter run -d linux"
echo "  Windows:  flutter run -d windows"
echo ""
echo "Connect a Rivr node via USB or BLE, then:"
echo "  1. Open Settings tab → Connect"
echo "  2. Choose BLE or USB Serial"
echo "  3. Select your device from the scan list"
