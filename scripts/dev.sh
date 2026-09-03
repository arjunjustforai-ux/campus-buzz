#!/usr/bin/env bash
# One-shot local dev: build functions, start emulators, seed, print next steps.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd functions && npm run build)
IMPORT=""
[ -f emulator-data/firebase-export-metadata.json ] && IMPORT="--import=./emulator-data"
firebase emulators:start --project demo-campusbuzz $IMPORT --export-on-exit=./emulator-data &
EMU=$!
echo "Waiting for emulators…"; for i in $(seq 1 60); do curl -sf http://localhost:8080 >/dev/null 2>&1 && break; sleep 1; done
(cd functions && npm run seed)
echo
echo "Emulator UI:  http://localhost:4000"
echo "Run the app:  flutter run -d chrome --dart-define=USE_EMULATORS=true --dart-define=CB_ENV=development"
echo "Demo login:   student@demo.campusbuzz.test / CampusBuzz!123 (see docs/DEMO_SCRIPT.md)"
wait $EMU
