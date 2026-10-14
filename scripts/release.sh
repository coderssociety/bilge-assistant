#!/bin/zsh
# Builds Bilge for release and packs it into a DMG under build/release.
#
# With a "Developer ID Application" certificate the app is signed for distribution and, when
# NOTARY_PROFILE names a profile saved with `xcrun notarytool store-credentials`, notarized and stapled.
# Without one the DMG is signed for development only: it opens on this Mac, and Gatekeeper warns elsewhere.
set -euo pipefail

root=${0:A:h:h}
output="$root/build/release"
archive="$output/Bilge.xcarchive"
staging="$output/dmg"

cd "$root"
rm -rf "$output"
mkdir -p "$output"

xcodegen generate --quiet
(cd Packages/AsistanKit && swift test --quiet)

xcodebuild -project Asistan.xcodeproj -scheme Asistan -configuration Release \
    -archivePath "$archive" -quiet archive

settings=$(xcodebuild -project Asistan.xcodeproj -scheme Asistan -configuration Release -showBuildSettings 2>/dev/null)
team=$(print -r -- "$settings" | awk -F' = ' '/ DEVELOPMENT_TEAM = / && !found { print $2; found = 1 }')

if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    if [[ -z "$team" ]]; then
        print -u2 "Hata: DEVELOPMENT_TEAM boş; Config/Signing.local.xcconfig dosyasına takım kimliğini yaz."
        exit 1
    fi
    options="$output/ExportOptions.plist"
    /usr/libexec/PlistBuddy -c "Add :method string developer-id" \
        -c "Add :teamID string $team" \
        -c "Add :signingStyle string automatic" "$options" >/dev/null
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$output/export" \
        -exportOptionsPlist "$options" -quiet
    app="$output/export/Bilge.app"
    distribution=true
else
    print -u2 "Uyarı: Developer ID sertifikası yok; DMG yalnızca geliştirme imzalı olacak."
    app="$archive/Products/Applications/Bilge.app"
    distribution=false
fi

codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
dmg="$output/Bilge-$version.dmg"

mkdir -p "$staging"
ditto "$app" "$staging/Bilge.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Bilge $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" -quiet
rm -rf "$staging"

if $distribution; then
    codesign --sign "Developer ID Application" --timestamp "$dmg"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$dmg"
        spctl --assess --type open --context context:primary-signature --verbose "$dmg"
    else
        print -u2 "Uyarı: NOTARY_PROFILE verilmedi; DMG notarize edilmedi."
    fi
fi

(cd "$output" && shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
print "$dmg"
