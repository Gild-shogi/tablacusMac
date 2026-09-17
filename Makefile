APP := TablacusMac.app
# Xcode なし（Command Line Tools のみ）だと swift test が Testing.framework を見つけられない
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
SIGN_ID := TablacusMac Local Signing

.PHONY: run test app icon signing-identity

run:
	swift run

test:
	swift test --disable-xctest -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)

app: signing-identity
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/TablacusMac $(APP)/Contents/MacOS/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	plutil -create xml1 $(APP)/Contents/Info.plist
	plutil -insert CFBundleExecutable -string TablacusMac $(APP)/Contents/Info.plist
	plutil -insert CFBundleIdentifier -string local.tablacus-mac $(APP)/Contents/Info.plist
	plutil -insert CFBundleName -string TablacusMac $(APP)/Contents/Info.plist
	plutil -insert CFBundlePackageType -string APPL $(APP)/Contents/Info.plist
	plutil -insert CFBundleIconFile -string AppIcon $(APP)/Contents/Info.plist
	plutil -insert NSAppleEventsUsageDescription -string "ゴミ箱に入れた項目を「戻す」で復元できるよう、削除を Finder に依頼します" $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" --identifier local.tablacus-mac $(APP)

# SVG を変えたときだけ実行する。rsvg-convert（brew install librsvg）が必要
icon:
	rm -rf AppIcon.iconset && mkdir AppIcon.iconset
	for size in 16 32 128 256 512; do \
		rsvg-convert -w $$size -h $$size Resources/AppIcon.svg -o AppIcon.iconset/icon_$${size}x$${size}.png && \
		rsvg-convert -w $$((size * 2)) -h $$((size * 2)) Resources/AppIcon.svg -o AppIcon.iconset/icon_$${size}x$${size}@2x.png || exit 1; \
	done
	iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
	rm -rf AppIcon.iconset

# アドホック署名だとビルドごとに別アプリ扱いになり、フォルダや Finder 操作の許可がリセットされるため固定の証明書で署名する
signing-identity:
	@security find-identity -p codesigning | grep -q "$(SIGN_ID)" || { \
		dir=$$(mktemp -d) && \
		/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$(SIGN_ID)" \
			-addext "extendedKeyUsage=critical,codeSigning" -addext "keyUsage=critical,digitalSignature" -addext "basicConstraints=critical,CA:false" \
			-keyout $$dir/key.pem -out $$dir/cert.pem 2>/dev/null && \
		/usr/bin/openssl pkcs12 -export -inkey $$dir/key.pem -in $$dir/cert.pem -out $$dir/id.p12 -passout pass:import && \
		security import $$dir/id.p12 -k ~/Library/Keychains/login.keychain-db -P import -T /usr/bin/codesign; \
		status=$$?; rm -rf $$dir; exit $$status; }
