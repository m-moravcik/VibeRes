.PHONY: app cli install-cli uninstall-cli test clean

DERIVED := $(shell xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -showBuildSettings 2>/dev/null | awk -F= '/ BUILD_DIR =/{print $$2}' | tr -d ' ')
RELEASE := $(DERIVED)/Release
PREFIX  ?= /usr/local

app:
	xcodegen generate
	xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -configuration Release \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build

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

clean:
	rm -rf VibeRes.xcodeproj
	rm -rf "$(DERIVED)"
