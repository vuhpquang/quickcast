#!/usr/bin/env bash
# Scripts/release.sh — cut a Quickcast release locally, end to end.
#
#   Scripts/release.sh 1.0.1                    # notes generated from commits
#   Scripts/release.sh 1.0.1 notes.md           # notes from a Markdown file
#   DRY_RUN=1 Scripts/release.sh 1.0.1          # build + verify + package only, then undo the bump
#   INSTALL=1 Scripts/release.sh 1.0.1          # also replace /Applications/Quickcast.app
#   SKIP_TESTS=1 ...                            # skip the harness suite (~6 min)
#
# Steps: preflight → bump project.yml + project.pbxproj → Scripts/run-tests.sh → xcodebuild
# Release (arm64) → verify the signer → zip + Ed25519 .sig + DMG → commit, tag, push main →
# GitHub release with Quickcast-X.Y.Z.{dmg,zip,zip.sig}.
#
# Installed copies only accept an update whose bundle satisfies their own designated requirement,
# i.e. is signed by RELEASE_CERT ("Quickcast Self-Signed"), so nothing else is ever published.
# The zip's .sig is made with the Ed25519 key whose public half is QuickcastUpdatePublicKey.

set -euo pipefail
cd "$(dirname "$0")/.."

REPO="vuhpquang/quickcast"
BRANCH="main"
BUNDLE_ID="com.vuhpquang.quickcast"
SIGN_IDENTITY="Quickcast Self-Signed"
RELEASE_CERT="14b035e45f99ac2b26af03ad6652b055e4e664d8"   # SHA-1 of that certificate
SIGNING_DIR="$HOME/.config/quickcast-signing"
PBXPROJ="Quickcast.xcodeproj/project.pbxproj"
DERIVED="build/release-dd"
APP="$DERIVED/Build/Products/Release/Quickcast.app"
# Fails on this Mac on untouched upstream Tinycast too (PTY streaming), so it never blocks a release.
KNOWN_FAILING="custom-command-test"
DRY_RUN="${DRY_RUN:-0}"

die()  { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

VERSION="${1:-}"
NOTES_FILE="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: Scripts/release.sh X.Y.Z [notes.md]"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || die "notes file not found: $NOTES_FILE"
TAG="v${VERSION}"
DMG="dist/Quickcast-${VERSION}.dmg"
ZIP="dist/Quickcast-${VERSION}.zip"

step "Preflight"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || die "release from '$BRANCH'"
[[ -z "$(git status --porcelain)" ]] || die "working tree not clean"
if [[ "$DRY_RUN" != "1" ]]; then
    git fetch -q origin "$BRANCH"
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCH")" ]] || die "$BRANCH is not in sync with origin"
    git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists on origin"
    gh auth status >/dev/null 2>&1 || die "gh is not logged in"
fi
security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\"" \
    || die "signing identity '$SIGN_IDENTITY' not in keychain (import $SIGNING_DIR/quickcast-signing.p12, password in p12-password.txt)"
if [[ -z "${UPDATE_SIGNING_KEY:-}" ]]; then
    [[ -f "$SIGNING_DIR/update-signing-key.txt" ]] || die "no UPDATE_SIGNING_KEY and no $SIGNING_DIR/update-signing-key.txt"
    UPDATE_SIGNING_KEY="$(cat "$SIGNING_DIR/update-signing-key.txt")"
fi
export UPDATE_SIGNING_KEY

CURRENT="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)"
BUILD="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)"
[[ -n "$CURRENT" && -n "$BUILD" ]] || die "cannot read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml"
newest="$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
[[ "$VERSION" != "$CURRENT" && "$newest" == "$VERSION" ]] || die "$VERSION must be newer than $CURRENT"
NEXT_BUILD=$((BUILD + 1))
echo "    $CURRENT (build $BUILD) → $VERSION (build $NEXT_BUILD)"

COMMITTED=0
undo() {
    if [[ "$DRY_RUN" == "1" || "$COMMITTED" == "0" ]]; then git checkout -q -- project.yml "$PBXPROJ"; fi
}
trap undo EXIT

step "Bumping project.yml and $PBXPROJ"
sed -i '' -E "s/^( *MARKETING_VERSION: )\".*\"/\1\"$VERSION\"/; s/^( *CURRENT_PROJECT_VERSION: )\".*\"/\1\"$NEXT_BUILD\"/" project.yml
sed -i '' -E "s/(MARKETING_VERSION = )[^;]*;/\1$VERSION;/; s/(CURRENT_PROJECT_VERSION = )[^;]*;/\1$NEXT_BUILD;/" "$PBXPROJ"

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
    step "Running tests (Scripts/run-tests.sh)"
    log="$(mktemp)"
    TMPDIR="$(mktemp -d)/" Scripts/run-tests.sh > "$log" 2>&1 || true
    tail -1 "$log"
    failed="$(sed -n 's/.*harness(es) failed in [0-9]*s: //p' "$log" | sed 's/\x1b\[[0-9;]*m//g')"
    for name in $failed; do
        [[ " $KNOWN_FAILING " == *" $name "* ]] || die "harness '$name' failed — see $log"
    done
    grep -q 'harness(es) passed\|harness(es) failed' "$log" || die "test suite did not finish — see $log"
fi

step "Building Release (arm64)"
rm -rf "$DERIVED"
xcodebuild -project Quickcast.xcodeproj -scheme Quickcast -configuration Release \
    -derivedDataPath "$DERIVED" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="" \
    -quiet build 2>&1 | grep -E 'error:|BUILD FAILED' && die "build failed"
[[ -d "$APP" ]] || die "build produced no $APP"

step "Verifying the release"
codesign --verify --deep --strict "$APP" || die "signature does not verify"
built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$built" == "$VERSION" ]] || die "bundle says $built, expected $VERSION"
bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$bid" == "$BUNDLE_ID" ]] || die "bundle id is $bid, expected $BUNDLE_ID"
codesign -d -r- "$APP" 2>&1 | grep -qiE "certificate (root|leaf) = H\"$RELEASE_CERT\"" \
    || die "Quickcast.app is not signed by the release certificate — installed copies would reject it"
[[ "$(lipo -archs "$APP/Contents/MacOS/Quickcast")" == *arm64* ]] || die "missing arm64 slice"

step "Packaging"
rm -rf dist && mkdir -p dist
# Only `ditto` keeps the signature verifiable; plain `zip` drops symlinks and the seal.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
Scripts/sign-update.swift "$APP" "$ZIP"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/Quickcast.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Quickcast -srcfolder "$STAGE" -format UDZO -ov "$DMG"
rm -rf "$STAGE"
codesign -s "$SIGN_IDENTITY" "$DMG"
for f in "$DMG" "$ZIP"; do echo "    $f  sha256 $(shasum -a 256 "$f" | awk '{print $1}')"; done

if [[ "$DRY_RUN" == "1" ]]; then
    step "Dry run — stopping before commit; version bump reverted. Artifacts are in dist/."
    exit 0
fi

step "Committing and tagging $TAG"
git add project.yml "$PBXPROJ"
git commit -q -m "release: $TAG"
COMMITTED=1
git tag -a "$TAG" -m "Quickcast $VERSION"
git push -q origin "$BRANCH" "$TAG"

step "Creating GitHub release $TAG"
notes=(--generate-notes)
[[ -n "$NOTES_FILE" ]] && notes=(--notes-file "$NOTES_FILE")
gh release create "$TAG" "$DMG" "$ZIP" "$ZIP.sig" -R "$REPO" \
    --title "Quickcast $VERSION" "${notes[@]}" --latest

if [[ "${INSTALL:-0}" == "1" ]]; then
    step "Installing to /Applications"
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    sleep 1
    rm -rf /Applications/Quickcast.app
    ditto "$APP" /Applications/Quickcast.app
    xattr -dr com.apple.quarantine /Applications/Quickcast.app 2>/dev/null || true
fi

step "Released Quickcast $VERSION"
echo "    https://github.com/$REPO/releases/tag/$TAG"
