APP_NAME       = JustType
BUNDLE_ID      = com.justype.app
BUILD_CONFIG   = release
BUILD_DIR      = .build/$(BUILD_CONFIG)
APP_BUNDLE     = build/$(APP_NAME).app
INSTALL_DIR    = /Applications

# IME (input method) sub-bundle. Lives inside the main app's Resources
# at runtime; the main app copies it to ~/Library/Input Methods/ when
# the user enables the beta feature in Settings.
IME_NAME       = JustTypeIME
IME_DISPLAY    = JustType IME
IME_BUNDLE_ID  = com.justype.app.ime
IME_APP_BUNDLE = build/$(IME_DISPLAY).app

# Dev build identifiers. The dev variant uses a distinct bundle ID +
# display name, so it co-exists peacefully with the installed
# /Applications/JustType.app — separate Accessibility grants, separate
# settings, separate menu-bar entry.
DEV_APP_NAME   = Dev
DEV_BUNDLE_ID  = com.justype.app.dev
DEV_APP_BUNDLE = build/$(DEV_APP_NAME).app

# Distribution-related paths. The notarization profile is created with
# `xcrun notarytool store-credentials JustType-Notary --apple-id ... --team-id ...`
# and stored in the user's login keychain.
NOTARY_PROFILE = JustType-Notary
ENTITLEMENTS   = Resources/JustType.entitlements
ZIP            = build/$(APP_NAME).zip
DMG            = build/$(APP_NAME).dmg
DMG_STAGING    = build/dmg-staging

# Resolve a stable code-signing identity at make-time. The script prefers a
# Developer ID Application cert (required for distribution + notarization),
# falls back to Apple Development for local-only builds, and otherwise
# creates a local self-signed cert.
SIGN_IDENTITY := $(shell ./scripts/get-sign-identity.sh)

.PHONY: all build run install clean bundle sign cert reset-tcc identity \
        zip dmg notarize staple release release-notarized \
        dev dev-run dev-bundle ime ime-bundle

all: bundle

build:
	swift build -c $(BUILD_CONFIG)

# Build the IME bundle (`JustType IME.app`) and stash it inside the main
# app's Resources/ so the released app can copy it to
# ~/Library/Input Methods/ at runtime when the user opts in.
ime-bundle: build
	@rm -rf "$(IME_APP_BUNDLE)"
	@mkdir -p "$(IME_APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(IME_APP_BUNDLE)/Contents/Resources"
	@cp $(BUILD_DIR)/$(IME_NAME) "$(IME_APP_BUNDLE)/Contents/MacOS/$(IME_NAME)"
	@cp Resources/IME-Info.plist "$(IME_APP_BUNDLE)/Contents/Info.plist"
	@if [ -f Resources/JustType.icns ]; then \
	    cp Resources/JustType.icns "$(IME_APP_BUNDLE)/Contents/Resources/JustType.icns"; \
	fi
	@if echo "$(SIGN_IDENTITY)" | grep -q "Developer ID"; then \
	    codesign --force --deep \
	        --sign "$(SIGN_IDENTITY)" \
	        --identifier $(IME_BUNDLE_ID) \
	        --options runtime \
	        --entitlements $(ENTITLEMENTS) \
	        --timestamp \
	        "$(IME_APP_BUNDLE)"; \
	else \
	    codesign --force --deep \
	        --sign "$(SIGN_IDENTITY)" \
	        --identifier $(IME_BUNDLE_ID) \
	        --timestamp=none \
	        "$(IME_APP_BUNDLE)"; \
	fi
	@echo ""
	@echo "Built IME bundle: $(IME_APP_BUNDLE)"

ime: ime-bundle

cert:
	@./scripts/ensure-cert.sh "JustType Local Sign"

identity:
	@echo "Signing identity: $(SIGN_IDENTITY)"

bundle: build ime-bundle
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@if [ -f Resources/JustType.icns ]; then \
	    cp Resources/JustType.icns $(APP_BUNDLE)/Contents/Resources/JustType.icns; \
	fi
	@# Embed the IME bundle inside the main app so we can lift it out at
	@# runtime into ~/Library/Input Methods/ when the user enables the beta.
	@cp -R "$(IME_APP_BUNDLE)" "$(APP_BUNDLE)/Contents/Resources/$(IME_DISPLAY).app"
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
	@killall "$(DEV_APP_NAME)" 2>/dev/null || true
	@killall "$(APP_NAME)" 2>/dev/null || true
	@open $(APP_BUNDLE)

# Build a dev variant — same source, different bundle ID + display name,
# no notarization. Lives in build/JustType Dev.app and shows up in the
# menu bar separately from the installed /Applications/JustType.app.
dev-bundle: build
	@# Prefer Apple Development cert for dev (no Gatekeeper warning + no
	@# notarization needed). Fall back to whatever get-sign-identity picks.
	@DEV_IDENTITY=$$( \
	    security find-identity -v -p codesigning 2>/dev/null \
	    | grep "Apple Development" | head -1 \
	    | sed -E 's/.*"([^"]+)".*/\1/' ); \
	if [ -z "$$DEV_IDENTITY" ]; then DEV_IDENTITY="$(SIGN_IDENTITY)"; fi; \
	echo "Dev signing identity: $$DEV_IDENTITY"; \
	rm -rf "$(DEV_APP_BUNDLE)"; \
	mkdir -p "$(DEV_APP_BUNDLE)/Contents/MacOS"; \
	mkdir -p "$(DEV_APP_BUNDLE)/Contents/Resources"; \
	cp $(BUILD_DIR)/$(APP_NAME) "$(DEV_APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	cp Resources/Info.plist "$(DEV_APP_BUNDLE)/Contents/Info.plist"; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(DEV_BUNDLE_ID)" "$(DEV_APP_BUNDLE)/Contents/Info.plist"; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleName $(DEV_APP_NAME)" "$(DEV_APP_BUNDLE)/Contents/Info.plist"; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $(DEV_APP_NAME)" "$(DEV_APP_BUNDLE)/Contents/Info.plist"; \
	if [ -f Resources/JustType.icns ]; then \
	    cp Resources/JustType.icns "$(DEV_APP_BUNDLE)/Contents/Resources/JustType.icns"; \
	fi; \
	codesign --force --deep \
	    --sign "$$DEV_IDENTITY" \
	    --identifier $(DEV_BUNDLE_ID) \
	    --timestamp=none \
	    "$(DEV_APP_BUNDLE)"
	@echo ""
	@echo "Built dev bundle: $(DEV_APP_BUNDLE)"
	@echo "Bundle ID:        $(DEV_BUNDLE_ID)"
	@echo "Display name:     $(DEV_APP_NAME)"
	@echo "Note: first run needs a one-time Accessibility grant for this dev variant."

dev: dev-bundle

dev-run: dev-bundle
	@# Quit any other JustType variant first — both binaries listen for the
	@# same trigger key, so they'd fight if left running together.
	@killall "$(DEV_APP_NAME)" 2>/dev/null || true
	@killall "$(APP_NAME)" 2>/dev/null || true
	@open "$(DEV_APP_BUNDLE)"

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

# Build a signed + notarized DMG containing the already-stapled .app.
# Provides the classic drag-to-Applications install experience. Depends
# on `staple` so the .app inside is already notarized + stapled — that
# way users can also extract the .app directly without internet.
dmg: staple
	@rm -rf $(DMG_STAGING)
	@mkdir -p $(DMG_STAGING)
	@cp -R $(APP_BUNDLE) $(DMG_STAGING)/
	@ln -s /Applications $(DMG_STAGING)/Applications
	@rm -f $(DMG)
	@hdiutil create \
	    -volname $(APP_NAME) \
	    -srcfolder $(DMG_STAGING) \
	    -ov -format UDZO \
	    $(DMG) >/dev/null
	@codesign --force --sign "$(SIGN_IDENTITY)" --timestamp $(DMG)
	@echo "Submitting $(DMG) to Apple notary…"
	@xcrun notarytool submit $(DMG) \
	    --keychain-profile "$(NOTARY_PROFILE)" \
	    --wait
	@xcrun stapler staple $(DMG)
	@xcrun stapler validate $(DMG)
	@spctl -a -t open --context context:primary-signature -vv $(DMG) 2>&1 || true
	@rm -rf $(DMG_STAGING)
	@echo ""
	@echo "Notarized + stapled DMG ready: $(DMG)"

# Convenience target: everything you need for a public release.
release-notarized: dmg
release: release-notarized

# One-time use: wipe stale Accessibility grants from the previous ad-hoc
# signing identity. Run this once after switching to the stable cert.
reset-tcc:
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@echo "Reset Accessibility TCC for $(BUNDLE_ID)."

clean:
	@rm -rf .build build
	@echo "Cleaned."
