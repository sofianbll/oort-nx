#!/usr/bin/env bash
# scripts/release.sh <version> [--engine-repo <url> --engine-commit <sha>] [--publish --notes <file>]
#
# Builds a release copy of NX Library (version in its plist, NXLibraryRelease marker, bundled
# runtime), verifies its signature and zips it as work/release/NXLibrary-<version>.zip, the asset
# the app's updater looks for, plus work/release/NXLibrary-<version>.dmg for a first install.
# Only --publish pushes v<version> and creates a GitHub release with both files, in the same
# verified repository (GitHub computes the zip's digest, which the app checks).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() { echo "usage: scripts/release.sh <version> [--engine-repo <url> --engine-commit <sha>] [--publish --notes <file>]" >&2; exit 2; }

VERSION="${1:-}"
[ -n "$VERSION" ] || usage
shift
PUBLISH=0
NOTES=""
ENGINE_REPO=""
ENGINE_COMMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --notes) [ $# -ge 2 ] && [ -n "$2" ] || usage; NOTES="$2"; shift ;;
    --engine-repo) [ $# -ge 2 ] && [ -n "$2" ] || usage; ENGINE_REPO="$2"; shift ;;
    --engine-commit) [ $# -ge 2 ] && [ -n "$2" ] || usage; ENGINE_COMMIT="$2"; shift ;;
    *) usage ;;
  esac
  shift
done

fail() { echo "error: $*" >&2; exit 1; }

resolve_release_repository() {
  local source="$1" default successor canonical
  default="$(sed -n 's/.*defaultRepository: String? = "\([^"]*\)".*/\1/p' "$source")"
  successor="$(sed -n 's/.*successorRepository: String? = "\([^"]*\)".*/\1/p' "$source")"
  [ -n "$default" ] || fail "no public update repository is configured"
  canonical="$(gh api "repos/$default" --hostname github.com --jq 'select(.private == false) | .full_name')" \
    || fail "could not look up the public update repository"
  [[ -n "$canonical" && ( "$canonical" == "$default" || "$canonical" == "$successor" ) ]] \
    || fail "the update repository must be public and match the configured fork or its successor"
  printf '%s\n' "$canonical"
}

check_release_tree() {
  local changes
  changes="$(git status --porcelain --untracked-files=all)" || fail "could not check the working tree"
  [ -z "$changes" ] || fail "the working tree has changes; commit or stash them first"
  if [ "$PRIVATE" = "0" ] && git rev-parse -q --verify "$TAG_REF" >/dev/null; then
    fail "the local tag $TAG already exists"
  fi
  [ "$(tr -d '[:space:]' < "$ROOT/VERSION")" = "$VERSION" ] \
    || fail "VERSION must match $VERSION"
}

release_refs() {
  local url="https://github.com/$REPOSITORY.git" effective
  effective="$(git ls-remote --get-url "$url")" || fail "could not resolve the release Git URL"
  [ "$effective" = "$url" ] \
    || fail "Git rewrites the URL for github.com/$REPOSITORY"
  git -c http.followRedirects=false ls-remote "$url" refs/heads/main "$TAG_REF" "$TAG_REF^{}" \
    || fail "could not read main and $TAG in github.com/$REPOSITORY"
}

check_publish_target() {
  local push_url refs
  [ "$(git rev-parse --verify HEAD)" = "$RELEASE_COMMIT" ] \
    || fail "HEAD changed during release preparation"
  push_url="$(git remote get-url --push --all origin)" || fail "could not read the origin push URL"
  case "${push_url%.git}" in
    "https://github.com/$REPOSITORY"|"git@github.com:$REPOSITORY"|"ssh://git@github.com/$REPOSITORY") ;;
    *) fail "origin push URL must point only to github.com/$REPOSITORY (the public release repository)" ;;
  esac
  refs="$(release_refs)"
  [ "$(awk '$2 == "refs/heads/main" { print $1 }' <<< "$refs")" = "$RELEASE_COMMIT" ] \
    || fail "HEAD is not the published main of github.com/$REPOSITORY; merge and push the release commit first"
  [ -z "$(awk -v tag="$TAG_REF" '$2 == tag || $2 == tag "^{}"' <<< "$refs")" ] \
    || fail "the remote tag $TAG already exists in github.com/$REPOSITORY"
}

# Check anonymous branch reachability, not merely existence in GitHub's fork network.
check_engine_pin() (
  local repo="$1" commit="$2" heads probe
  probe="$(mktemp -d)" || return 1
  trap 'rm -rf "$probe"' EXIT
  cd "$probe" || return 1
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS
  export HOME="$probe" XDG_CONFIG_HOME="$probe" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false
  heads="$(git -c http.followRedirects=false ls-remote --exit-code --heads "$repo")" || return 1
  if ! awk -v pin="$commit" '$1 == pin { found = 1 } END { exit !found }' <<< "$heads"; then
    git -c http.followRedirects=false clone --quiet --bare --filter=blob:none --no-tags "$repo" checkout \
      || return 1
    [ -n "$(git -C checkout for-each-ref --count=1 --contains="$commit" refs/heads)" ]
  fi
)

[[ "$VERSION" =~ ^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){2}$ ]] || fail "use MAJOR.MINOR.PATCH, like 0.3.0"
TAG="v$VERSION"
TAG_REF="refs/tags/$TAG"

# Private Google client: published builds never receive these variables.
if [ "$PUBLISH" = "1" ] && [ -n "${ARCANE_GOOGLE_CLIENT_ID+x}${ARCANE_GOOGLE_CLIENT_SECRET+x}" ]; then
  fail "unset ARCANE_GOOGLE_CLIENT_ID and ARCANE_GOOGLE_CLIENT_SECRET before using --publish"
fi
GOOGLE_CLIENT_ID="${ARCANE_GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${ARCANE_GOOGLE_CLIENT_SECRET:-}"
unset ARCANE_GOOGLE_CLIENT_ID ARCANE_GOOGLE_CLIENT_SECRET
PRIVATE=0
if [[ "$GOOGLE_CLIENT_ID" =~ [^[:space:]] && "$GOOGLE_CLIENT_SECRET" =~ [^[:space:]] ]]; then PRIVATE=1; fi

check_release_tree
if [ "$PUBLISH" = "1" ]; then
  [ -n "$NOTES" ] && [ -f "$NOTES" ] || fail "--publish needs --notes <file> with the release notes"
  command -v gh >/dev/null || fail "--publish needs the GitHub CLI (gh)"
  REPOSITORY="$(resolve_release_repository "$ROOT/Sources/NXLibraryCore/App/AppUpdate.swift")"
  RELEASE_COMMIT="$(git rev-parse --verify HEAD)" || fail "could not resolve the release commit"
  check_publish_target
fi

MIN_XCODE="$(sed -n 's/.*minimumXcode: "\([0-9.]*\)".*/\1/p' "$ROOT/Sources/ArcanePorting/Setup/ToolchainRequirements.swift" | head -1)"
ENGINE="${ENGINE_COMMIT:-$(sed -n 's/.*let defaultPinnedEngineCommit = "\([0-9a-f]\{40\}\)".*/\1/p' "$ROOT/Sources/NXLibrary/ViewModels/AppViewModel.swift" | head -1)}"
[ -n "$MIN_XCODE" ] && [ -n "$ENGINE" ] || fail "could not read minimumXcode or defaultPinnedEngineCommit from the sources"

# An implicit pin uses the app's upstream engine; a partially supplied override is never valid.
ENGINE_TARGET="$ENGINE_REPO"
if [[ -n "$ENGINE_REPO$ENGINE_COMMIT" ]]; then
  [ -n "$ENGINE_REPO" ] && [ -n "$ENGINE_COMMIT" ] || fail "supply both --engine-repo and --engine-commit"
fi
if [ "$PUBLISH" = "1" ]; then
  ENGINE_TARGET="${ENGINE_TARGET:-$(sed -n 's/.*let engineRemote = "\([^"]*\)".*/\1/p' "$ROOT/Sources/ArcanePorting/Setup/SetupActions.swift")}"
  [ -n "$ENGINE_TARGET" ] || fail "could not read the default engine repository from the sources"
fi
if [ -n "$ENGINE_TARGET" ]; then
  [[ "$ENGINE_TARGET" =~ ^https://github\.com/[A-Za-z0-9_-]+/[A-Za-z0-9_-][A-Za-z0-9_.-]*$ ]] \
    || fail "--engine-repo must be an HTTPS GitHub repository URL"
  [[ "$ENGINE" =~ ^[0-9a-f]{40}$ ]] \
    || fail "--engine-commit must be the full 40-character lowercase SHA"
  check_engine_pin "$ENGINE_TARGET" "$ENGINE" \
    || fail "engine commit $ENGINE must be reachable from a public branch of $ENGINE_TARGET"
fi
# Always pass the validated pair (or empty values), never ambient build options.
export NX_ENGINE_REPO="$ENGINE_REPO" NX_ENGINE_COMMIT="$ENGINE_COMMIT"

# Every release is tested from its own tree.
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift test --package-path "$ROOT" \
  || fail "swift test failed"
for check in "$ROOT"/Tests/CatalogAppChecks/run_*.py; do
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" python3 "$check" \
    || fail "application regressions failed: ${check##*/}"
done
(cd "$ROOT" && python3 -m unittest discover -s Tests/PublicationChecks >/dev/null 2>&1) \
  || fail "the publication checks' tests failed (python3 -m unittest discover -s Tests/PublicationChecks)"
[ -d "$ROOT/work/Runtime" ] || fail "no work/Runtime: run scripts/bundle_runtime.sh first (a release carries its Python and tools)"
python3 "$ROOT/scripts/check_publication.py" --runtime "$ROOT/work/Runtime"

# What this release needs on a player's Mac, as a hidden line in its notes (AppUpdate.requirements(in:)): the
# update dialog warns about an Xcode to update first and the engine Setup downloads after the restart.
REQUIRES="<!-- nxlibrary-requires xcode=$MIN_XCODE engine=$ENGINE -->"
echo "Requires: Xcode $MIN_XCODE, nxnative ${ENGINE:0:7}"

OUT="$ROOT/work/release"
if [ "$PRIVATE" = "1" ]; then OUT="$ROOT/work/release-private"; fi
# Keep the legacy archive root for installed updaters; the DMG has the display name.
APP="$OUT/NXLibrary.app"
ZIP="$OUT/NXLibrary-$VERSION.zip"
rm -rf "$OUT"
mkdir -p "$OUT"

if [ "$PRIVATE" = "1" ]; then
  ARCANE_GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" ARCANE_GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
    NX_VERSION="$VERSION" NX_RELEASE=1 bash "$ROOT/scripts/build_app.sh" "$APP"
else
  NX_VERSION="$VERSION" NX_RELEASE=1 bash "$ROOT/scripts/build_app.sh" "$APP"
fi
unset GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET
codesign --verify --deep --strict "$APP"
if [ "$PUBLISH" = "1" ]; then
  /usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
  for key in ArcaneGoogleClientID ArcaneGoogleClientSecret; do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
      fail "the built Info.plist contains a private Google OAuth key; nothing was published"
    fi
  done
fi
if /usr/libexec/PlistBuddy -c 'Print :NXLibraryDevelopmentProfile' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  fail "a release must not select the development data profile"
fi
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION" ] \
  || fail "the built app does not carry version $VERSION"
[ "$(/usr/libexec/PlistBuddy -c 'Print :NXLibraryRelease' "$APP/Contents/Info.plist")" = "true" ] \
  || fail "the built app is not marked as a release"
if [[ -n "$ENGINE_REPO" ]]; then
  [ "$(/usr/bin/plutil -extract NXLibraryEngineRepository raw "$APP/Contents/Info.plist")" = "$ENGINE_REPO" ] \
    && [ "$(/usr/bin/plutil -extract NXLibraryEngineCommit raw "$APP/Contents/Info.plist")" = "$ENGINE_COMMIT" ] \
    || fail "the built app does not carry the requested engine pin"
fi

# Finder metadata becomes AppleDouble sidecars in a ZIP; release bundles need only
# their sealed files and relative links, not those extra unsealed resources.
ditto --norsrc -c -k --keepParent "$APP" "$ZIP"
"$APP/Contents/Resources/Runtime/python/bin/python3" -I -B \
  "$APP/Contents/Resources/validate_update.py" "$ZIP" "$OUT/.update-check"
codesign --verify --deep --strict "$OUT/.update-check/NXLibrary.app"
python3 "$ROOT/scripts/check_localizations.py" --app "$OUT/.update-check/NXLibrary.app"
rm -rf "$OUT/.update-check"
echo "Zip: $ZIP"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
DMG="$OUT/NXLibrary-$VERSION.dmg"
bash "$ROOT/scripts/build_dmg.sh" "$APP"
mv "$ROOT/dist/NXLibrary.dmg" "$DMG"
echo "DMG: $DMG"

if [ "$PUBLISH" = "1" ]; then
  {
    cat "$NOTES"
    if [[ -n "$ENGINE_REPO" ]]; then
      printf '\n\n## Moteur épinglé\n\n- Dépôt : %s\n- Commit : `%s`.\n' "$ENGINE_REPO" "$ENGINE_COMMIT"
    fi
    printf '\n\n%s\n' "$REQUIRES"
  } > "$OUT/notes.md"
  # Packaging takes time: repeat the guards just before the first write.
  check_engine_pin "$ENGINE_TARGET" "$ENGINE" \
    || fail "engine commit $ENGINE is no longer verified on a public branch of $ENGINE_TARGET"
  check_release_tree
  [ "$(resolve_release_repository "$ROOT/Sources/NXLibraryCore/App/AppUpdate.swift")" = "$REPOSITORY" ] \
    || fail "the public update repository changed during release preparation"
  check_publish_target
  git tag "$TAG" "$RELEASE_COMMIT" || fail "could not create the local tag $TAG"
  tag_object="$(git rev-parse --verify "$TAG_REF")" || fail "could not resolve the local tag $TAG"
  [ "$(git rev-parse --verify "$tag_object^{commit}")" = "$RELEASE_COMMIT" ] \
    || fail "the local tag $TAG does not point to the expected commit"
  git -c http.followRedirects=false push --no-follow-tags --recurse-submodules=no origin "$tag_object:$TAG_REF" \
    || fail "could not confirm push of $TAG to github.com/$REPOSITORY; check the tag before retrying"
  refs="$(release_refs)"
  tag_commit="$(awk -v tag="$TAG_REF" '$2 == tag { direct = $1 } $2 == tag "^{}" { peeled = $1 }
    END { print (peeled == "" ? direct : peeled) }' <<< "$refs")"
  [ "$tag_commit" = "$RELEASE_COMMIT" ] \
    || fail "$TAG does not resolve to the expected commit in github.com/$REPOSITORY; no release created"
  gh release create "$TAG" "$ZIP" "$DMG" --repo "github.com/$REPOSITORY" --verify-tag \
    --title "Oort NX $VERSION" --notes-file "$OUT/notes.md" \
    || fail "the tag was pushed but release creation or upload was not confirmed; check github.com/$REPOSITORY before retrying"
  echo "Published $TAG"
else
  echo "Not published (add --publish --notes <file> to create the GitHub release)."
fi
