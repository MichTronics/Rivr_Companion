#!/usr/bin/env bash
# build.sh — Bouw Rivr Companion met jouw server-instellingen.
#
# Vul hieronder je URL en sleutel in, dan:
#   bash build.sh              → Android APK (debug)
#   bash build.sh apk          → Android APK (release)
#   bash build.sh appbundle    → Android App Bundle (release, voor Play Store)
#   bash build.sh linux        → Linux desktop (release)
#   bash build.sh windows      → Windows desktop (release)
#   bash build.sh run          → Draaien op verbonden apparaat / emulator
#
set -euo pipefail

# ─── INSTELLINGEN ─────────────────────────────────────────────────────────────

INGEST_URL="https://rivr.co.nl"
INGEST_TOKEN="98c99b3d29f338e3519a094dc1950fc791a19a029f5cda70f74f20d43cd2e1fd"                   # ← vul hier je verbindingssleutel in

# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET="${1:-apk}"

DEFINES="--dart-define=INGEST_URL=${INGEST_URL} --dart-define=INGEST_TOKEN=${INGEST_TOKEN}"

echo "==> Rivr Companion build"
echo "    URL   : ${INGEST_URL}"
echo "    Token : ${INGEST_TOKEN:+(ingesteld)}"
echo "    Target: ${TARGET}"
echo ""

case "$TARGET" in
  apk)
    flutter build apk --release $DEFINES
    echo ""
    echo "APK: build/app/outputs/flutter-apk/app-release.apk"
    ;;
  appbundle)
    flutter build appbundle --release $DEFINES
    echo ""
    echo "Bundle: build/app/outputs/bundle/release/app-release.aab"
    ;;
  linux)
    flutter build linux --release $DEFINES
    echo ""
    echo "Binary: build/linux/x64/release/bundle/"
    ;;
  windows)
    flutter build windows --release $DEFINES
    echo ""
    echo "Binary: build/windows/x64/runner/Release/"
    ;;
  run)
    flutter run $DEFINES
    ;;
  *)
    echo "Onbekend target: $TARGET"
    echo "Gebruik: apk | appbundle | linux | windows | run"
    exit 1
    ;;
esac
