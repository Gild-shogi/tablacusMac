APP := TablacusMac.app
# Xcode なし（Command Line Tools のみ）だと swift test が Testing.framework を見つけられない
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks

.PHONY: run test app

run:
	swift run

test:
	swift test --disable-xctest -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/TablacusMac $(APP)/Contents/MacOS/
	plutil -create xml1 $(APP)/Contents/Info.plist
	plutil -insert CFBundleExecutable -string TablacusMac $(APP)/Contents/Info.plist
	plutil -insert CFBundleIdentifier -string local.tablacus-mac $(APP)/Contents/Info.plist
	plutil -insert CFBundleName -string TablacusMac $(APP)/Contents/Info.plist
	plutil -insert CFBundlePackageType -string APPL $(APP)/Contents/Info.plist
