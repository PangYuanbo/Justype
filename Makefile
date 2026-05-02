APP_NAME      = JustType
BUNDLE_ID     = com.justype.app
BUILD_CONFIG  = release
BUILD_DIR     = .build/$(BUILD_CONFIG)
APP_BUNDLE    = build/$(APP_NAME).app
INSTALL_DIR   = /Applications

# Resolve a stable code-signing identity at make-time. The script prefers an
# existing Apple Development/Distribution cert and otherwise creates a local
# self-signed cert. A stable identity keeps the app's Designated Requirement
# (and thus its TCC / Accessibility grant) constant across rebuilds.
SIGN_IDENTITY := $(shell ./scripts/get-sign-identity.sh)

.PHONY: all build run install clean bundle sign cert reset-tcc identity

all: bundle

build:
	swift build -c $(BUILD_CONFIG)

cert:
	@./scripts/ensure-cert.sh "JustType Local Sign"

identity:
	@echo "Signing identity: $(SIGN_IDENTITY)"

bundle: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@$(MAKE) sign
	@echo ""
	@echo "Built: $(APP_BUNDLE)"

sign:
	@codesign --force --deep \
		--sign "$(SIGN_IDENTITY)" \
		--identifier $(BUNDLE_ID) \
		--timestamp=none \
		$(APP_BUNDLE)
	@echo "Signed as: $(SIGN_IDENTITY)"
	@codesign -dvv $(APP_BUNDLE) 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true

run: bundle
	@open $(APP_BUNDLE)

install: bundle
	@rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

# One-time use: wipe stale Accessibility grants from the previous ad-hoc
# signing identity. Run this once after switching to the stable cert.
reset-tcc:
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@echo "Reset Accessibility TCC for $(BUNDLE_ID)."

clean:
	@rm -rf .build build
	@echo "Cleaned."
