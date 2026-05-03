APP_NAME       = JustType
BUNDLE_ID      = com.justype.app
BUILD_CONFIG   = release
BUILD_DIR      = .build/$(BUILD_CONFIG)
APP_BUNDLE     = build/$(APP_NAME).app
INSTALL_DIR    = /Applications

# Distribution-related paths. The notarization profile is created with
# `xcrun notarytool store-credentials JustType-Notary --apple-id ... --team-id ...`
# and stored in the user's login keychain.
NOTARY_PROFILE = JustType-Notary
ENTITLEMENTS   = Resources/JustType.entitlements
ZIP            = build/$(APP_NAME).zip

# Resolve a stable code-signing identity at make-time. The script prefers a
# Developer ID Application cert (required for distribution + notarization),
# falls back to Apple Development for local-only builds, and otherwise
# creates a local self-signed cert.
SIGN_IDENTITY := $(shell ./scripts/get-sign-identity.sh)

.PHONY: all build run install clean bundle sign cert reset-tcc identity \
        zip notarize staple release release-notarized

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
	@if [ -f Resources/JustType.icns ]; then \
	    cp Resources/JustType.icns $(APP_BUNDLE)/Contents/Resources/JustType.icns; \
	fi
	@$(MAKE) sign
	@echo ""
	@echo "Built: $(APP_BUNDLE)"

# Sign with hardened runtime + entitlements + secure timestamp when a
# Developer ID cert is in use; otherwise fall back to the simpler local
# signing flow used for development.
sign:
	@if echo "$(SIGN_IDENTITY)" | grep -q "Developer ID"; then \
	    codesign --force --deep \
	        --sign "$(SIGN_IDENTITY)" \
	        --identifier $(BUNDLE_ID) \
	        --options runtime \
	        --entitlements $(ENTITLEMENTS) \
	        --timestamp \
	        $(APP_BUNDLE); \
	else \
	    codesign --force --deep \
	        --sign "$(SIGN_IDENTITY)" \
	        --identifier $(BUNDLE_ID) \
	        --timestamp=none \
	        $(APP_BUNDLE); \
	fi
	@echo "Signed as: $(SIGN_IDENTITY)"
	@codesign -dvv $(APP_BUNDLE) 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Runtime|flags" || true

run: bundle
	@open $(APP_BUNDLE)

install: bundle
	@rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

# Pack the .app into a Notary-friendly zip (preserves extended attributes
# via ditto). Used as input to notarytool and as the release artifact.
zip: bundle
	@rm -f $(ZIP)
	@ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(ZIP)
	@echo "Created: $(ZIP)"

# Submit to Apple for notarization. Blocks until the result comes back.
# Requires `xcrun notarytool store-credentials $(NOTARY_PROFILE)` to have
# been run once on this machine.
notarize: zip
	@echo "Submitting $(ZIP) to Apple notary…"
	@xcrun notarytool submit $(ZIP) \
	    --keychain-profile "$(NOTARY_PROFILE)" \
	    --wait
	@echo "Notarization done."

# Staple the notarization ticket onto the .app, then re-zip so the staple
# is included in what gets distributed.
staple: notarize
	@xcrun stapler staple $(APP_BUNDLE)
	@xcrun stapler validate $(APP_BUNDLE)
	@rm -f $(ZIP)
	@ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(ZIP)
	@spctl -a -vv $(APP_BUNDLE) 2>&1 || true
	@echo ""
	@echo "Notarized + stapled bundle ready: $(APP_BUNDLE)"
	@echo "Distributable archive:           $(ZIP)"

# Convenience target: everything you need for a public release.
release-notarized: staple
release: release-notarized

# One-time use: wipe stale Accessibility grants from the previous ad-hoc
# signing identity. Run this once after switching to the stable cert.
reset-tcc:
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@echo "Reset Accessibility TCC for $(BUNDLE_ID)."

clean:
	@rm -rf .build build
	@echo "Cleaned."
