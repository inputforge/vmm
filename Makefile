VMM := .build/release/vmm
ENTITLEMENTS := vmm.entitlements
CONFIG ?= test.json
SIGN_IDENTITY ?= -

.PHONY: build sign run smoke clean

build:
	swift build -c release

sign: build
	codesign --force \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_IDENTITY)" \
		$(VMM)

run: sign
	$(VMM) run $(CONFIG)

smoke: sign
	! $(VMM) nope
	! $(VMM) run missing.json

clean:
	swift package clean
