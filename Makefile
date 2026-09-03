# CampusBuzz developer commands. See README.md.
FLUTTER ?= flutter
DEFINES = --dart-define=USE_EMULATORS=true --dart-define=CB_ENV=development

.PHONY: setup functions emulators seed run-web run-android test test-functions test-rules test-flutter analyze ci

setup: ## Install Flutter + functions dependencies
	$(FLUTTER) pub get
	cd functions && npm install

functions: ## Build Cloud Functions
	cd functions && npm run build

emulators: functions ## Start the Firebase Emulator Suite (auth, firestore, functions, storage, ui)
	firebase emulators:start --project demo-campusbuzz --import=./emulator-data --export-on-exit=./emulator-data

seed: ## Seed the running emulator with the JAGSoM demo campus (emulator only)
	cd functions && npm run seed

run-web: ## Run the app in Chrome against the emulator
	$(FLUTTER) run -d chrome $(DEFINES)

run-android: ## Run on an Android emulator (uses 10.0.2.2 automatically)
	$(FLUTTER) run -d android $(DEFINES)

analyze:
	$(FLUTTER) analyze
	cd functions && npm run lint

test-flutter:
	$(FLUTTER) test

test-functions:
	cd functions && npm run build && npm test

test-rules: functions
	firebase emulators:exec --only firestore,auth --project demo-campusbuzz "cd functions && FIRESTORE_EMULATOR_HOST=localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 GCLOUD_PROJECT=demo-campusbuzz npx vitest run tests/integration tests/rules"

test: analyze test-flutter test-functions test-rules ## Full validation gate

ci: test
