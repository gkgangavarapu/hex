#!/bin/sh
# Keeps this fork tracking anomalyco/hex's stable releases.
#
# The fork has two long-lived branches:
#   stable  a clean mirror of upstream's newest stable release tag (vX.Y.Z)
#   intel   `stable` plus this fork's Intel build patches (the default branch)
#
# This script finds the newest non-prerelease vX.Y.Z tag on the upstream
# remote, moves `stable` to it, merges it into `intel`, and pushes both.
# A conflict aborts the merge, leaves the branches alone, and (in Actions)
# opens one issue with the conflicted files so the merge can be finished by
# hand. It is run daily by .github/workflows/upstream-sync.yml and can be run
# by hand from a checkout of `intel`:
#
#   scripts/sync-upstream-stable.sh            # sync and push
#   DRY_RUN=1 scripts/sync-upstream-stable.sh  # report only, change nothing
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

upstream_url=${UPSTREAM_URL:-https://github.com/anomalyco/hex.git}
remote=${UPSTREAM_REMOTE:-upstream}
intel_branch=${INTEL_BRANCH:-intel}
stable_branch=${STABLE_BRANCH:-stable}

git config user.name >/dev/null 2>&1 || git config user.name "hex-intel-sync"
git config user.email >/dev/null 2>&1 || git config user.email "${SYNC_EMAIL:-hex-intel-sync@users.noreply.github.com}"

if ! git remote get-url "$remote" >/dev/null 2>&1; then
  git remote add "$remote" "$upstream_url"
fi
git fetch --force --tags "$remote"

latest=$(git tag --list 'v*' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V \
  | tail -n 1)
if [ -z "$latest" ]; then
  echo "No stable vX.Y.Z tag found on $upstream_url" >&2
  exit 1
fi
target=$(git rev-parse "$latest^{commit}")
echo "Upstream stable release: $latest ($target)"

if [ "${DRY_RUN:-}" = 1 ]; then
  echo "DRY_RUN=1: not moving $stable_branch or merging into $intel_branch"
  exit 0
fi

moved=false
current_stable=$(git rev-parse --verify -q "refs/heads/$stable_branch" || true)
if [ "$current_stable" != "$target" ]; then
  git push origin "$target:refs/heads/$stable_branch"
  echo "$stable_branch -> $latest"
  moved=true
else
  echo "$stable_branch already at $latest"
fi

if [ "$(git rev-parse --abbrev-ref HEAD)" != "$intel_branch" ]; then
  git checkout -q "$intel_branch"
fi
# The remote-tracking ref follows the push above, so keep it current for the
# status line below.
git fetch -q origin "$intel_branch" || true

if git merge-base --is-ancestor "$target" HEAD; then
  echo "$intel_branch already contains $latest"
  if [ "$moved" = true ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "Upstream stable **$latest** mirrored to \`$stable_branch\`; \`$intel_branch\` already contained it." >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

summary="Upstream stable **$latest**"
if git merge --no-edit -m "Merge upstream stable $latest into $intel_branch" "$target"; then
  git push origin "$intel_branch"
  echo "$intel_branch merged $latest"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$summary merged into \`$intel_branch\`." >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

# Conflict: keep the branches as they were and say exactly what clashed.
conflicted=$(git diff --name-only --diff-filter=U)
git merge --abort
{
  echo "Upstream stable $latest could not be merged into $intel_branch automatically."
  echo
  echo "Conflicted files:"
  printf '%s\n' "$conflicted" | sed 's/^/- /'
  echo
  echo "Resolve locally, then re-run the Track upstream stable workflow:"
  echo
  echo '```sh'
  echo "git fetch upstream --tags"
  echo "git checkout $intel_branch"
  echo "git merge $latest   # fix conflicts, commit"
  echo "git push origin $intel_branch"
  echo '```'
} >"$root/.git/upstream-sync-conflict.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "**Conflict** merging upstream stable $latest into \`$intel_branch\`:" >> "$GITHUB_STEP_SUMMARY"
  printf '%s\n' '```' >> "$GITHUB_STEP_SUMMARY"
  printf '%s\n' "$conflicted" >> "$GITHUB_STEP_SUMMARY"
  printf '%s\n' '```' >> "$GITHUB_STEP_SUMMARY"
fi
if [ -n "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  title="Upstream sync conflict: $latest"
  existing=$(gh issue list --state open --search "$title in:title" --json number --jq '.[0].number' 2>/dev/null || true)
  if [ -n "$existing" ]; then
    echo "Conflict already reported in issue #$existing" >&2
    gh issue comment "$existing" --body-file "$root/.git/upstream-sync-conflict.md" >/dev/null 2>&1 || true
  else
    gh issue create --title "$title" --body-file "$root/.git/upstream-sync-conflict.md" >/dev/null || true
  fi
fi
echo "Conflict merging $latest into $intel_branch; see .git/upstream-sync-conflict.md" >&2
exit 1
