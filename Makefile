VMM := .build/apple/Products/Release/vmm
ENTITLEMENTS := vmm.entitlements
CONFIG ?= examples/linux.json
SIGN_IDENTITY ?= -

.PHONY: build sign run smoke clean

build:
	swift build -c release --arch arm64 --arch x86_64

sign: build
	codesign --force \
		--options runtime \
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
