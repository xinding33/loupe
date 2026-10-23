SWIFT_FLAGS = --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
export CLANG_MODULE_CACHE_PATH = $(CURDIR)/.build/module-cache
export SWIFTPM_MODULECACHE_OVERRIDE = $(CURDIR)/.build/module-cache

.PHONY: build test check format app
build:
	swift build $(SWIFT_FLAGS)
test:
	swift test $(SWIFT_FLAGS)
format:
	xcrun swift-format format -i -r Sources Tests Package.swift
check:
	xcrun swift-format lint --strict -r Sources Tests Package.swift
	swift test $(SWIFT_FLAGS)
# dist/Loupe.app, signed with this Mac's Developer ID when it has one. See scripts/build.sh.
app:
	SWIFT_BUILD_FLAGS="$(SWIFT_FLAGS)" bash scripts/build.sh
