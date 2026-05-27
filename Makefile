SWIFT_VM := .build/release/swift-vm
ENTITLEMENTS := swift-vm.entitlements
CONFIG ?= test.json
SIGN_IDENTITY ?= -

.PHONY: build sign run smoke clean

build:
	swift build -c release

sign: build
	codesign --force \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_IDENTITY)" \
		$(SWIFT_VM)

run: sign
	$(SWIFT_VM) run $(CONFIG)

smoke: sign
	! $(SWIFT_VM)
	! $(SWIFT_VM) run missing.json

clean:
	swift package clean
