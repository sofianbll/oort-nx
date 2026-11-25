#!/usr/bin/env bash
# scripts/release.sh <version> [--plain-dmg] [--engine-repo <url> --engine-commit <sha>] [--publish --notes <file>]
#
# Builds a release copy of NX Library (version in its plist, NXLibraryRelease marker, bundled
# runtime), verifies its signature and zips it as work/release/Oort-NX-<version>.zip, the asset
# the app's updater looks for, plus work/release/Oort-NX-<version>.dmg for a first install.
# Only --publish pushes v<version> and creates a GitHub release with both files, in the same
# verified repository (GitHub computes the zip's digest, which the app checks).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() { echo "usage: scripts/release.sh <version> [--plain-dmg] [--engine-repo <url> --engine-commit <sha>] [--publish --notes <file>]" >&2; exit 2; }

VERSION="${1:-}"
[ -n "$VERSION" ] || usage
shift
PUBLISH=0
PLAIN_DMG=0
NOTES=""
ENGINE_REPO=""
ENGINE_COMMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --plain-dmg) PLAIN_DMG=1 ;;
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
  canonical="$(gh api "repos/$default" --hostname github.com --jq 'select(.private == false and .permissions.push == true) | .full_name')" \
    || fail "could not look up the public update repository"
  [[ -n "$canonical" && ( "$canonical" == "$default" || "$canonical" == "$successor" ) ]] \
    || fail "the update repository must be public, grant push access, and match the configured fork or its successor"
  printf '%s\n' "$canonical"
}

check_release_tree() {
  local changes
  changes="$(git status --porcelain --untracked-files=all)" || fail "could not check the working tree"
  [ -z "$changes" ] || fail "the working tree has changes; commit or stash them first"
  if [ "$PRIVATE" = "0" ] && [ "$PUBLISH" = "0" ] && git rev-parse -q --verify "$TAG_REF" >/dev/null; then
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
  local push_url refs local_tag remote_tag
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
  local_tag="$(git rev-parse -q --verify "$TAG_REF" || true)"
  remote_tag="$(awk -v tag="$TAG_REF" '$2 == tag { print $1 }' <<< "$refs")"
  RESUME_TAG=0
  if [ -n "$remote_tag" ]; then
    [ "$remote_tag" = "$local_tag" ] || fail "the remote tag $TAG already exists and is not the identical local tag"
    [ "$(git rev-parse --verify "$local_tag^{commit}")" = "$RELEASE_COMMIT" ] \
      || fail "the local tag $TAG does not point to the expected commit"
    RESUME_TAG=1
  elif [ -n "$local_tag" ]; then
    fail "the local tag $TAG already exists without the identical published tag"
  fi
  check_release_absent
}

check_release_absent() {
  local releases
  # A successful authenticated list includes drafts; a failed request is not absence.
  releases="$(gh api "repos/$REPOSITORY/releases" --hostname github.com --paginate --jq '.[].tag_name')" \
    || fail "could not list releases in github.com/$REPOSITORY"
  if grep -Fxq -- "$TAG" <<< "$releases"; then
    fail "a release for $TAG already exists in github.com/$REPOSITORY"
  fi
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
ENGINE_TARGET="${ENGINE_REPO:-$(sed -n 's/.*let engineRemote = "\([^"]*\)".*/\1/p' "$ROOT/Sources/ArcanePorting/Setup/SetupActions.swift")}"
if [[ -n "$ENGINE_REPO$ENGINE_COMMIT" ]]; then
  [ -n "$ENGINE_REPO" ] && [ -n "$ENGINE_COMMIT" ] || fail "supply both --engine-repo and --engine-commit"
fi
[[ "$ENGINE_TARGET" =~ ^https://github\.com/[A-Za-z0-9_-]+/[A-Za-z0-9_-][A-Za-z0-9_.-]*$ ]] \
    || fail "--engine-repo must be an HTTPS GitHub repository URL"
[[ "$ENGINE" =~ ^[0-9a-f]{40}$ ]] \
    || fail "--engine-commit must be the full 40-character lowercase SHA"

engine_probe="$(mktemp -d)" || fail "could not create the engine test directory"
trap 'rm -rf "$engine_probe"' EXIT
(
  cd "$engine_probe"
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS
  export HOME="$engine_probe" XDG_CONFIG_HOME="$engine_probe" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false
  git -c http.followRedirects=false clone --quiet --no-checkout --no-tags "$ENGINE_TARGET" checkout &&
    [ -n "$(git -C checkout for-each-ref --count=1 --contains="$ENGINE" refs/remotes/origin)" ]
) || fail "engine commit $ENGINE must be reachable from a public branch of $ENGINE_TARGET"
# Always pass the validated pair (or empty values), never ambient build options.
export NX_ENGINE_REPO="$ENGINE_REPO" NX_ENGINE_COMMIT="$ENGINE_COMMIT"

# Every release is tested from its own tree.
NX_TEST_ENGINE_REPO="$engine_probe/checkout" NX_TEST_ENGINE_COMMIT="$ENGINE" NX_TEST_ENGINE_REQUIRED=1 \
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
# The archive, the app inside it and the DMG carry the display name.
APP="$OUT/Oort NX.app"
ZIP="$OUT/Oort-NX-$VERSION.zip"
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
codesign --verify --deep --strict "$OUT/.update-check/Oort NX.app"
python3 "$ROOT/scripts/check_localizations.py" --app "$OUT/.update-check/Oort NX.app"
python3 "$ROOT/scripts/check_publication.py" --app "$OUT/.update-check/Oort NX.app"
rm -rf "$OUT/.update-check"
echo "Zip: $ZIP"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
DMG="$OUT/Oort-NX-$VERSION.dmg"
if [ "$PLAIN_DMG" = 1 ]; then
  bash "$ROOT/scripts/build_dmg.sh" --plain "$APP"
else
  bash "$ROOT/scripts/build_dmg.sh" "$APP"
fi
mv "$ROOT/dist/Oort NX.dmg" "$DMG"
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
  if [ "$RESUME_TAG" = "0" ]; then
    git tag "$TAG" "$RELEASE_COMMIT" || fail "could not create the local tag $TAG"
  fi
  tag_object="$(git rev-parse --verify "$TAG_REF")" || fail "could not resolve the local tag $TAG"
  [ "$(git rev-parse --verify "$tag_object^{commit}")" = "$RELEASE_COMMIT" ] \
    || fail "the local tag $TAG does not point to the expected commit"
  if [ "$RESUME_TAG" = "0" ]; then
    git -c http.followRedirects=false push --no-follow-tags --recurse-submodules=no origin "$tag_object:$TAG_REF" \
      || fail "could not confirm push of $TAG to github.com/$REPOSITORY; check the tag before retrying"
  fi
  refs="$(release_refs)"
  [ "$(awk -v tag="$TAG_REF" '$2 == tag { print $1 }' <<< "$refs")" = "$tag_object" ] \
    || fail "the remote tag is not identical to $TAG; no release created"
  tag_commit="$(awk -v tag="$TAG_REF" '$2 == tag { direct = $1 } $2 == tag "^{}" { peeled = $1 }
    END { print (peeled == "" ? direct : peeled) }' <<< "$refs")"
  [ "$tag_commit" = "$RELEASE_COMMIT" ] \
    || fail "$TAG does not resolve to the expected commit in github.com/$REPOSITORY; no release created"
  check_release_absent
  gh release create "$TAG" "$ZIP" "$DMG" --repo "github.com/$REPOSITORY" --verify-tag \
    --title "Oort NX $VERSION" --notes-file "$OUT/notes.md" \
    || fail "the tag was pushed but release creation or upload was not confirmed; check github.com/$REPOSITORY before retrying"
  echo "Published $TAG"
else
  echo "Not published (add --publish --notes <file> to create the GitHub release)."
fi
