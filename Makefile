SCHEME := ICCery
DEST := 'platform=macOS'

.PHONY: gen build test universal fetch-argyll clean

gen:
	xcodegen generate

build: gen
	xcodebuild build -scheme $(SCHEME) -destination $(DEST)

test: gen
	xcodebuild build test -scheme $(SCHEME) -destination $(DEST)

universal: gen
	xcodebuild build -scheme $(SCHEME) -destination $(DEST) \
		ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO

fetch-argyll:
	scripts/fetch-argyll.sh

clean:
	rm -rf ICCery.xcodeproj DerivedData Packages/ICCeryCore/.build
