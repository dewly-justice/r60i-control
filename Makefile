# One-command build for the app, the probe and the tests. See README.md.

APP_NAME      := R60i Control
PROJECT       := R60iControl.xcodeproj
SCHEME        := R60iControl
CONFIGURATION ?= Release
BUILD_DIR     := build
DERIVED       := $(BUILD_DIR)/DerivedData
APP_PATH      := $(BUILD_DIR)/$(APP_NAME).app

# Sign with your Apple Development certificate if you have one (keeps the Bluetooth
# permission across rebuilds); otherwise sign ad hoc.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"Apple Development' && echo "Apple Development" || echo "-")
# The team ID comes from that certificate (its OU field); ad hoc signing needs none.
TEAM_ID ?= $(if $(filter -,$(SIGN_IDENTITY)),,$(shell security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p'))

.PHONY: app run project test probe clean

app: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" DEVELOPMENT_TEAM="$(TEAM_ID)" -quiet build
	rm -rf "$(APP_PATH)"
	cp -R "$(DERIVED)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app" "$(APP_PATH)"
	@echo "Built $(APP_PATH)"

run: app
	open "$(APP_PATH)"

project:
	@command -v xcodegen >/dev/null || { echo "XcodeGen is missing: brew install xcodegen"; exit 1; }
	xcodegen generate --quiet

test:
	swift test --package-path SoundcoreKit

# make probe ARGS="--hexdump set-mode anc"
probe:
	swift run --package-path SoundcoreKit scprobe $(ARGS)

clean:
	rm -rf $(BUILD_DIR) $(PROJECT) SoundcoreKit/.build
