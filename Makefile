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
# The scheme's tests are the UI tests, which `make screenshots` runs.
TEST_APP_PLATFORMS := none

include .apple-ci/apple.mk

RESULTS ?= $(CURDIR)/.build/results
SCREENSHOTS ?= $(CURDIR)/.build/screenshots
SCREENSHOT_SCRIPT := .github/scripts/screenshots.py

.PHONY: help bootstrap test build-package check-icons screenshots ci-linux ci-macos clean

help:
	@echo "make bootstrap    XcodeGen and the Xcode project"
	@echo "make signing TEAM=…   your team, in Signing.xcconfig (git ignores it)"
	@echo "make test         the package's tests (macOS and Linux)"
	@echo "make build        the app and its widgets for the iOS Simulator and the Mac, unsigned"
	@echo "make screenshots  the UI tests on the Mac and an iPhone simulator, and their screenshots"
	@echo "make ci-linux | ci-macos   what CI runs"

bootstrap: tools project

# The package and the CLI; no warnings in our code (CLAUDE.md).
build-package:
	$(SWIFT) build

test: swift-test

# The built apps have their icons (after make build).
check-icons:
	.github/scripts/check-app-icons.sh $(DERIVED_DATA)

# The UI tests on the Mac (signed to run locally, without the entitlements an app without a
# provisioning profile can't launch with) and on the newest iPhone simulator, then their
# screenshots, kept in .build/screenshots and printed into the log (App/README.md).
screenshots: project
	@mkdir -p $(RESULTS)
	@rm -rf $(RESULTS)/mac.xcresult $(RESULTS)/iphone.xcresult
	@status=0; \
	$(XCODEBUILD) test -project $(XCODEPROJ) -scheme $(SCHEME) -destination 'platform=macOS' \
	  -derivedDataPath $(DERIVED_DATA) -resultBundlePath $(RESULTS)/mac.xcresult \
	  $(SIGNED_LOCALLY) CODE_SIGN_ENTITLEMENTS= ENABLE_HARDENED_RUNTIME=NO || status=1; \
	device=$$($(PYTHON) $(SCREENSHOT_SCRIPT) pick-iphone) && \
	$(XCODEBUILD) test -project $(XCODEPROJ) -scheme $(SCHEME) -destination "platform=iOS Simulator,id=$$device" \
	  -derivedDataPath $(DERIVED_DATA) -resultBundlePath $(RESULTS)/iphone.xcresult $(UNSIGNED) || status=1; \
	$(PYTHON) $(SCREENSHOT_SCRIPT) collect $(RESULTS) $(SCREENSHOTS) || status=1; \
	$(PYTHON) $(SCREENSHOT_SCRIPT) print $(SCREENSHOTS) || status=1; \
	$(PYTHON) $(SCREENSHOT_SCRIPT) failures $(RESULTS) || status=1; \
	exit $$status

ci-linux: build-package test

ci-macos: build-package build check-icons test

clean:
	rm -rf $(XCODEPROJ) .build/DerivedData $(RESULTS) $(SCREENSHOTS)
