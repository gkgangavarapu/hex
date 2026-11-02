# Intel macOS builds (this fork)

Upstream Hex ships macOS builds for Apple silicon only. This fork adds a
repeatable Intel (x86_64) build on top of upstream's stable releases.

## Branches

| Branch | What it is |
| --- | --- |
| `stable` | A clean mirror of `anomalyco/hex`'s newest stable release tag (`vX.Y.Z`). Never carries fork changes. |
| `intel` | Default branch. `stable` plus the small patches below. All Intel builds come from here. |
| `dev` | Left as upstream's development branch was at fork time; not tracked. |

## Tracking upstream stable

`.github/workflows/upstream-sync.yml` runs daily (and on demand from the
Actions tab). It finds the newest non-prerelease `vX.Y.Z` tag on
`anomalyco/hex`, force-updates `stable` to that tag, merges it into `intel`,
and pushes. If the merge conflicts, it aborts the merge, leaves `intel`
untouched (`stable` has already moved to the new tag), and opens one issue
named "Upstream sync conflict: vX.Y.Z" listing the conflicted files.

The logic lives in `scripts/sync-upstream-stable.sh` and can be run by hand
from a checkout of `intel`:

```sh
scripts/sync-upstream-stable.sh              # sync and push
DRY_RUN=1 scripts/sync-upstream-stable.sh    # report only
```

`intel` is the fork's default branch, so GitHub schedules this workflow from
it. Workflows are enabled in this fork; if GitHub ever pauses them (a fork
whose Actions were never enabled starts paused), open the Actions tab and
click **Enable workflows**. The schedule runs daily at 04:17 UTC.

## Fork patches carried on `intel`

Kept deliberately small so daily merges stay clean:

1. `src/updater.rs` and `scripts/build-app.sh` — a build flagged
   `HEX_INTEL_BUILD=1` never checks for updates. Upstream's release service
   only publishes arm64 macOS builds, so an automatic update would replace the
   Intel app with one this Mac cannot run. Updates happen by reinstalling a
   newer DMG from this fork.
2. `scripts/build-intel-local.sh` — builds the unsigned, ad-hoc-signed
   `Hex.app` and `hex-<version>-macos-x64.dmg`.
3. `.github/workflows/upstream-sync.yml` and
   `scripts/sync-upstream-stable.sh` — the tracking automation above.
4. `docs/intel-macos.md` — this file.

Everything else is upstream code.

## Building locally

```sh
scripts/build-intel-local.sh
```

Outputs `dist/hex-<version>-macos-x64.dmg` (and a `.zip` plus `SHA256SUMS`).

Requirements:

- An Intel Mac.
- Full **Xcode 26 or newer**. Hex builds against the macOS 26 SDK
  (`SpeechAnalyzer`/`SpeechTranscriber`, `FoundationModels`); Command Line
  Tools alone cannot build it. The Universal Xcode 26 build still runs on
  Intel Macs; select it with:
  `sudo xcode-select -s /Applications/Xcode.app`
- A Rust toolchain (`rustup`) and `jq`.

The DMG is ad-hoc signed, not notarized. Install by opening the DMG and
dragging `Hex.app` to Applications; the first launch needs right-click → Open
(or `xattr -dr com.apple.quarantine /Applications/Hex.app`).

`LSMinimumSystemVersion` is 15.0, so the Intel build runs on macOS 15 and
later Intel Macs.

## Building without a local Xcode 26

`.github/workflows/build-macos-intel.yml` is **manual only** (never scheduled).
Dispatched from this fork's Actions tab (or `gh workflow run "Build Intel macOS
app"`), it builds on GitHub's standard x64 `macos-26-intel` runner — which has
Xcode 26 and a native x86_64 toolchain — and attaches the DMG to a release
tagged `intel-v<version>` in this fork. That is the path when no Mac with
Xcode 26 is available.

Both paths produce the same unsigned, ad-hoc-signed DMG; neither publishes to
upstream's release service.
