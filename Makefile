# Can I Retire Yet?: every command a contributor, an agent and CI run. The targets follow the
# build contract the j23n apps share (j23n/apple-ci); .apple-ci/apple.mk is a copy of its rules
# (`make update-apple-ci` refreshes it). On Linux, put /opt/swift/usr/bin on the PATH first
# (CLAUDE.md).

SHELL := /bin/bash
PYTHON ?= python3

PROJECT_SPEC := project.yml
XCODEPROJ := CanIRetireYet.xcodeproj
# Where your team and bundle identifier were before Signing.xcconfig: make project warns while it exists.
SIGNING_OLD := App/Config/Local.xcconfig
SCHEME := CanIRetireYet
PLATFORMS := ios mac
SWIFT_PACKAGES := .
# The app's unit tests (App/Tests) run on the Mac, signed to run locally without the entitlements an
# app without a provisioning profile can't launch with. `make screenshots` runs the scheme's screen
# tests.
TEST_APP_PLATFORMS := mac
TEST_APP_FLAGS := -only-testing:CanIRetireYetTests CODE_SIGN_ENTITLEMENTS= ENABLE_HARDENED_RUNTIME=NO

include .apple-ci/apple.mk

RESULTS ?= $(CURDIR)/.build/results
SCREENSHOTS ?= $(CURDIR)/.build/screenshots
SCREENSHOT_SCRIPT := .github/scripts/screenshots.py
SCREEN_TESTS := CanIRetireYetScreenTests

.PHONY: help bootstrap test build-package check-icons screenshots ci-linux ci-macos ci-macos-app clean

help:
	@echo "make bootstrap    XcodeGen and the Xcode project"
	@echo "make signing TEAM=…   your team, in Signing.xcconfig (git ignores it)"
	@echo "make test         the package's tests (macOS and Linux)"
	@echo "make build        the app and its widgets for the iOS Simulator and the Mac, unsigned"
	@echo "make test-app     the app's unit tests (App/Tests) on the Mac"
	@echo "make screenshots  each screen on the Mac and an iPhone simulator, as pictures in .build/screenshots"
	@echo "make ci-linux | ci-macos | ci-macos-app   what CI runs"

bootstrap: tools project

# The package and the CLI; no warnings in our code (CLAUDE.md).
build-package:
	$(SWIFT) build

test: swift-test

# The built apps have their icons (after make build).
check-icons:
	.github/scripts/check-app-icons.sh $(DERIVED_DATA)

# The screen tests (App/ScreenTests) on the Mac (signed to run locally, without the entitlements an
# app without a provisioning profile can't launch with, or its sandbox, so they can write their
# pictures) and on the newest iPhone simulator, booted while the Mac's run builds. Their pictures
# go to .build/screenshots (TEST_RUNNER_ hands SCREENSHOTS_DIR to the tests) and into the log
# (App/README.md, "Screenshots").
screenshots: project
	@mkdir -p $(RESULTS)
	@rm -rf $(RESULTS)/mac.xcresult $(RESULTS)/iphone.xcresult $(SCREENSHOTS)
	@status=0; \
	device=$$($(PYTHON) $(SCREENSHOT_SCRIPT) pick-iphone) && xcrun simctl boot "$$device" || true; \
	export TEST_RUNNER_SCREENSHOTS_DIR='$(SCREENSHOTS)'; \
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) test -project $(XCODEPROJ) -scheme $(SCHEME) -destination 'platform=macOS' \
	  -only-testing:$(SCREEN_TESTS) -derivedDataPath $(DERIVED_DATA) -resultBundlePath $(RESULTS)/mac.xcresult \
	  $(SIGNED_LOCALLY) CODE_SIGN_ENTITLEMENTS= ENABLE_HARDENED_RUNTIME=NO || status=1; \
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) test -project $(XCODEPROJ) -scheme $(SCHEME) -destination "platform=iOS Simulator,id=$$device" \
	  -only-testing:$(SCREEN_TESTS) -derivedDataPath $(DERIVED_DATA) -resultBundlePath $(RESULTS)/iphone.xcresult \
	  $(UNSIGNED) || status=1; \
	$(PYTHON) $(SCREENSHOT_SCRIPT) print $(SCREENSHOTS) || status=1; \
	$(PYTHON) $(SCREENSHOT_SCRIPT) failures $(RESULTS) || status=1; \
	exit $$status

ci-linux: build-package test

# The Mac's run on main and by hand: the app for the iOS Simulator and the Mac, its icons, its unit
# tests, and CloudSync's tests, the only package tests with Apple-only code. Linux builds and tests
# the whole package on every push, and building the app builds every package module it links.
ci-macos: build check-icons test-app
	$(SWIFT) test --filter CloudSyncTests

# A pull request's Mac run (ci.yml): the app for the Mac and its unit tests. The iOS Simulator's
# build, whose iPhone-only code is a few hundred lines, waits for main, or a ci:ios label.
ci-macos-app: build-mac test-app

clean:
	rm -rf $(XCODEPROJ) .build/DerivedData $(RESULTS) $(SCREENSHOTS)
