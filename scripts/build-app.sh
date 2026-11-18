#!/bin/zsh
# Build a universal mlisb.app into dist/ and zip it.
# Signing: set SIGN_IDENTITY="Developer ID Application: …" or leave unset for ad-hoc.
# Notarizing: also set NOTARY_PROFILE to a `xcrun notarytool store-credentials` profile name
# (and NOTARY_KEYCHAIN if that profile is not in the default keychain).
set -euo pipefail
cd ${0:A:h}/..
version=${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0.0.0)}
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)

# The diagram page is a build input that is not in git.
(cd render && pnpm install --frozen-lockfile && pnpm build)
(cd app && xcodegen generate)
derived=app/.build/release
xcodebuild -project app/mlisb.xcodeproj -scheme mlisb -configuration Release -derivedDataPath $derived \
  -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION=$version CURRENT_PROJECT_VERSION=$build \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build  # no get-task-allow: notarization rejects it

rm -rf dist && mkdir -p dist
app=dist/mlisb.app
ditto $derived/Build/Products/Release/mlisb.app $app

identity=${SIGN_IDENTITY:--}
# Notarization requires a secure timestamp; ad-hoc signatures can't have one.
timestamp=(--timestamp)
[[ $identity == - ]] && timestamp=(--timestamp=none)
sign() { codesign --force --options runtime $timestamp --sign "$identity" "$@" }
# Re-signing drops entitlements, so carry over the ones Xcode resolved for each bundle.
sign_keeping_entitlements() {
  local plist=$(mktemp)
  codesign -d --entitlements - --xml "$1" > $plist 2>/dev/null
  sign --entitlements $plist "$1"
  rm $plist
}
# Inside out, as Sparkle documents for Developer ID; --deep would drop the Downloader's entitlements.
sparkle=$app/Contents/Frameworks/Sparkle.framework/Versions/B
sign $sparkle/XPCServices/Installer.xpc
sign --preserve-metadata=entitlements $sparkle/XPCServices/Downloader.xpc
sign $sparkle/Autoupdate
sign $sparkle/Updater.app
sign $app/Contents/Frameworks/Sparkle.framework
for extension in $app/Contents/PlugIns/*.appex; do sign_keeping_entitlements $extension; done
sign_keeping_entitlements $app
codesign --verify --deep --strict $app

(cd dist && ditto -c -k --keepParent mlisb.app mlisb-$version.zip)

if [[ -n ${NOTARY_PROFILE:-} ]]; then
  notary_keychain=()
  [[ -n ${NOTARY_KEYCHAIN:-} ]] && notary_keychain=(--keychain $NOTARY_KEYCHAIN)
  xcrun notarytool submit dist/mlisb-$version.zip --keychain-profile $NOTARY_PROFILE \
    $notary_keychain --wait
  xcrun stapler staple $app
  rm dist/mlisb-$version.zip
  (cd dist && ditto -c -k --keepParent mlisb.app mlisb-$version.zip)
fi

shasum -a 256 dist/*.zip
