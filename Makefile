.PHONY: app signed-app signed-app-dry cli install-cli uninstall-cli test ui-test clean

DERIVED := $(shell xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -showBuildSettings 2>/dev/null | awk -F= '/ BUILD_DIR =/{print $$2}' | tr -d ' ')
RELEASE := $(DERIVED)/Release
PREFIX  ?= /usr/local

# ENABLE_HARDENED_RUNTIME=NO for the same reason Debug builds set it in
# project.yml: the hardened runtime enables library validation, and an
# ad-hoc-signed binary refuses to load the Developer ID-signed
# Sparkle.framework ("different Team IDs" at launch). Signed releases keep
# the hardened runtime — scripts/release-signed.sh re-signs Sparkle with the
# same team instead.
app:
	xcodegen generate
	xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -configuration Release \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
		ENABLE_HARDENED_RUNTIME=NO build

# Release build: real Developer ID signature, notarized and stapled.
# See scripts/release-signed.sh for the credentials it expects.
signed-app:
	./scripts/release-signed.sh

# Same, minus the Apple round-trip. Use this to check the certificate resolves
# and the signature carries hardened runtime + timestamp before submitting.
signed-app-dry:
	SKIP_NOTARIZE=1 ./scripts/release-signed.sh

cli:
	xcodegen generate
	xcodebuild -project VibeRes.xcodeproj -scheme viberes-cli -configuration Release \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build

install-cli: cli
	@mkdir -p $(PREFIX)/bin
	@cp -f "$(RELEASE)/viberes" $(PREFIX)/bin/viberes
	@chmod +x $(PREFIX)/bin/viberes
	@echo "Installed: $(PREFIX)/bin/viberes"
	@echo "Try: viberes list"

uninstall-cli:
	@rm -f $(PREFIX)/bin/viberes
	@echo "Removed: $(PREFIX)/bin/viberes"

test:
	xcodegen generate
	xcodebuild -project VibeRes.xcodeproj -scheme VibeRes test \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Drives the real app through the accessibility API — the only way to assert
# that a resolution row is a button and not a tap gesture. Needs Accessibility
# permission for the test runner (System Settings > Privacy & Security >
# Accessibility); CI runners already have it.
ui-test:
	xcodegen generate
	xcodebuild -project VibeRes.xcodeproj -scheme VibeResUI test \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

clean:
	rm -rf VibeRes.xcodeproj
	rm -rf "$(DERIVED)"
