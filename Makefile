APP_NAME     = Imperator DockFolders
SLUG         = Imperator-DockFolders
PROJECT      = DockFolders/DockFolders.xcodeproj
SCHEME       = DockFolders
DERIVED      = build/dd
BUNDLE       = $(DERIVED)/Build/Products/Release/$(APP_NAME).app
DIST         = dist
ZIP          = $(DIST)/$(SLUG)-$(VERSION).zip
PBXPROJ      = DockFolders/DockFolders.xcodeproj/project.pbxproj
BUILD_NUMBER = $(shell git rev-list --count HEAD)
IDENTITY     = $(or $(CODESIGN_IDENTITY),Imperator Dev)

# xcodebuild needs full Xcode; a Command Line Tools-only xcode-select fails.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: check-version build dist release verify clean

check-version:
	@test -n "$(VERSION)" || { echo "Usage: make $(MAKECMDGOALS) VERSION=1.0.0"; exit 1; }

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) build

# Distributable zip. Touches nothing in git, nothing on the remote.
dist: check-version build
	@mkdir -p $(DIST)
	rm -f "$(ZIP)"
	# Stamp the version into the BUILT bundle, not the source, so a test zip
	# reports the version it will ship as without dirtying the working tree.
	# Editing Info.plist breaks the signature, so re-sign after. --deep because
	# the bundle carries nested code (Contents/MacOS/mousepos).
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign "$(IDENTITY)" "$(BUNDLE)"
	codesign --verify --strict "$(BUNDLE)"
	ditto -c -k --sequesterRsrc --keepParent "$(BUNDLE)" "$(ZIP)"
	@echo "Built $(ZIP)"

# Bump version, commit, tag, push, publish the GitHub release with the zip attached.
release: check-version
	@git diff --quiet && git diff --cached --quiet || { echo "Working tree dirty -- commit first."; exit 1; }
	sed -i '' 's/MARKETING_VERSION = .*/MARKETING_VERSION = $(VERSION);/g' $(PBXPROJ)
	sed -i '' 's/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $(BUILD_NUMBER);/g' $(PBXPROJ)
	$(MAKE) dist VERSION=$(VERSION)
	git add $(PBXPROJ)
	git commit -m "Release v$(VERSION)"
	git tag -a v$(VERSION) -m "$(APP_NAME) $(VERSION)"
	git push origin HEAD
	git push origin v$(VERSION)
	gh release create v$(VERSION) \
		--title "$(APP_NAME) $(VERSION)" \
		--notes-file RELEASE_NOTES.md \
		"$(ZIP)#$(APP_NAME) $(VERSION) (macOS)"

# Check the app inside the zip, not the one in build/ -- the zip is what people download.
verify: check-version
	rm -rf /tmp/relcheck && mkdir -p /tmp/relcheck
	unzip -q "$(ZIP)" -d /tmp/relcheck
	/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "/tmp/relcheck/$(APP_NAME).app/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "/tmp/relcheck/$(APP_NAME).app/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Print :NSHumanReadableCopyright" "/tmp/relcheck/$(APP_NAME).app/Contents/Info.plist"
	lipo -info "/tmp/relcheck/$(APP_NAME).app/Contents/MacOS/Imperator DockFolders"
	test -x "/tmp/relcheck/$(APP_NAME).app/Contents/MacOS/mousepos" || { echo "mousepos helper MISSING from zip"; exit 1; }
	codesign --verify --strict --verbose=1 "/tmp/relcheck/$(APP_NAME).app"
	codesign -dvvv "/tmp/relcheck/$(APP_NAME).app" 2>&1 | grep ^Authority

clean:
	rm -rf $(DERIVED) $(DIST)
