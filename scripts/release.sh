#!/usr/bin/env bash
# Bump the version from the last v* tag, rewrite CHANGELOG.md, commit, tag,
# push, and create the GitHub release. Versioning is tag-only: nothing in
# the repository is stamped with a version string.
#
# Every function takes its inputs as arguments and keeps everything else
# `local`. A function that produces a value echoes exactly that value to
# stdout and nothing else; a function that only guards prints nothing on
# success. Failure is always die() + exit, never a return code to check.
#
# Configurable via environment: RELEASE_TEST_CMD, RELEASE_LINT_CMD and
# RELEASE_BRANCH override the pre-release gate for repos that don't use
# `just` or don't default to `main`.
set -euo pipefail

: "${RELEASE_TEST_CMD:=just test}"
: "${RELEASE_LINT_CMD:=just lint}"
: "${RELEASE_BRANCH:=main}"

die() {
  echo "❌ $*" >&2
  exit 1
}

check_preconditions() {
  [ -z "$(git status --porcelain)" ] || die "Working tree is not clean."
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  [ "$current_branch" = "$RELEASE_BRANCH" ] || die "Not on $RELEASE_BRANCH (on $current_branch)."
  $RELEASE_LINT_CMD || die "Lint failed ($RELEASE_LINT_CMD)."
  $RELEASE_TEST_CMD || die "Tests failed ($RELEASE_TEST_CMD)."
}

# Next version = last v*-tag, bumped by $1 (a semver release type, as
# node-semver's `semver.inc(version, releaseType)` names the same argument).
# No tag yet -> 0.0.0, so e.g. `bump_version minor` cuts the first release as
# 0.1.0.
bump_version() {
  local release_type="$1"
  local last_tag current major minor patch
  last_tag="$(git tag -l 'v*' --sort=-v:refname | head -1)"
  current="${last_tag#v}"
  current="${current:-0.0.0}"
  IFS='.' read -r major minor patch <<<"$current"
  case "$release_type" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) die "release type must be patch, minor or major (got: $release_type)" ;;
  esac
  echo "${major}.${minor}.${patch}"
}

# A marker must appear exactly once, or a drifted changelog is rejected
# instead of a substitution silently landing on the wrong line (sed does not
# error when its pattern matches nothing, so it could also land nowhere).
# Restores CHANGELOG.md first. Nothing is committed yet at this point.
require_exactly_one_match() {
  local pattern="$1" count
  count="$(grep -c -- "$pattern" CHANGELOG.md || true)"
  if [ "$count" != 1 ]; then
    git checkout -- CHANGELOG.md
    die "Expected exactly 1 match for '$pattern' in CHANGELOG.md, found $count. CHANGELOG.md is unchanged; nothing was committed."
  fi
}

replace_exactly_one() {
  local pattern="$1" replacement="$2"
  require_exactly_one_match "$pattern"
  sed -i "s|$pattern|$replacement|" CHANGELOG.md
}

# Turns the [Unreleased] section into the dated [version] section, then
# reopens a fresh [Unreleased] above it from the <!-- next-header/url -->
# anchors, so the changelog is ready for the next round of changes.
#
# Checks every marker it needs up front, so a drifted changelog is rejected
# before anything is touched, rather than after some of it already is.
update_changelog() {
  local version="$1" tag="$2" date="$3" repository="$4"

  require_exactly_one_match '## \[Unreleased\]'
  require_exactly_one_match '\[Unreleased\]: '
  require_exactly_one_match '<!-- next-header -->'
  require_exactly_one_match '<!-- next-url -->'

  replace_exactly_one "## \[Unreleased\]" "## [${version}] - ${date}"
  replace_exactly_one "\[Unreleased\]: " "[${version}]: "
  # On the first release, [Unreleased] still points at commits/HEAD, not at
  # a compare/vX...HEAD link; either way the HEAD becomes the new tag.
  if grep -q -- '\.\.\.HEAD' CHANGELOG.md; then
    replace_exactly_one "\.\.\.HEAD" "...${tag}"
  else
    replace_exactly_one "commits/HEAD" "commits/${tag}"
  fi
  replace_exactly_one "<!-- next-header -->" "<!-- next-header -->\n\n## [Unreleased]"
  replace_exactly_one "<!-- next-url -->" "<!-- next-url -->\n[Unreleased]: ${repository}/compare/${tag}...HEAD"
}

commit_and_tag() {
  local version="$1" tag="$2"
  git add CHANGELOG.md
  git commit -m "Release ${version}"
  # Annotated: `git push --follow-tags` only pushes annotated tags.
  git tag -a "${tag}" -m "Release ${version}"
}

# Everything before this point is local and can still be undone
# (git reset --hard, git tag -d). This is the point of no return.
confirm_and_push() {
  local tag="$1"
  echo
  echo "--- CHANGELOG.md changes for ${tag} ---"
  git --no-pager diff HEAD~1 -- CHANGELOG.md
  echo
  local reply
  read -rp "Push ${tag} to origin and publish the GitHub release? [y/N] " reply
  if [ "$reply" != y ] && [ "$reply" != Y ]; then
    echo "⏭️  Aborted before push. Local commit and tag ${tag} are left in place." >&2
    exit 0
  fi
  git push --follow-tags
}

# Cuts the section between this version's heading and the next `##` heading
# out of CHANGELOG.md, dropping both heading lines. That is the release notes.
changelog_notes_for() {
  local version="$1"
  sed -n '/^## \['"${version}"'\]/,/^## \[/{/^## \['"${version}"'\]/d;/^## \[/d;p}' CHANGELOG.md
}

publish_release() {
  local tag="$1" version="$2"
  if gh release view "$tag" >/dev/null 2>&1; then
    echo "⏭️  GitHub release $tag already exists"
  else
    changelog_notes_for "$version" | gh release create "$tag" --title "$tag" --notes-file -
  fi
}

main() {
  local release_type="${1:?usage: release.sh <patch|minor|major>}"

  check_preconditions

  local version tag date repository
  version="$(bump_version "$release_type")"
  tag="v${version}"
  date="$(date +%F)"
  repository="$(gh repo view --json url -q .url)"

  update_changelog "$version" "$tag" "$date" "$repository"
  commit_and_tag "$version" "$tag"
  confirm_and_push "$tag"
  publish_release "$tag" "$version"

  echo ""
  echo "✅ Released ${tag}"
}

# Guarded so tests can `source` this file to call individual functions
# without running the whole release.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
