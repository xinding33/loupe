SWIFT_FLAGS = --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
export CLANG_MODULE_CACHE_PATH = $(CURDIR)/.build/module-cache
export SWIFTPM_MODULECACHE_OVERRIDE = $(CURDIR)/.build/module-cache
BUILD_FINGERPRINT = sha256-$(shell { find Sources -type f -name '*.swift' -exec shasum -a 256 {} \; ; shasum -a 256 Package.swift Resources/Info.plist Makefile; } | LC_ALL=C sort | shasum -a 256 | cut -d ' ' -f 1)

.PHONY: build test check format app build-fingerprint
build:
	swift build $(SWIFT_FLAGS)
build-fingerprint:
	@printf '%s\n' '$(BUILD_FINGERPRINT)'
test:
	swift test $(SWIFT_FLAGS)
format:
	xcrun swift-format format -i -r Sources Tests Package.swift
check:
	xcrun swift-format lint --strict -r Sources Tests Package.swift
	swift test $(SWIFT_FLAGS)
app: build
	mkdir -p "dist/Artifact Lens.app/Contents/MacOS"
	cp "$$(swift build $(SWIFT_FLAGS) --show-bin-path)/ArtifactLens" "dist/Artifact Lens.app/Contents/MacOS/ArtifactLens"
	cp Resources/Info.plist "dist/Artifact Lens.app/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :ArtifactLensBuildFingerprint string $(BUILD_FINGERPRINT)" "dist/Artifact Lens.app/Contents/Info.plist"
	codesign --force --sign - "dist/Artifact Lens.app"
