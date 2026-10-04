# CI, releases, and Homebrew

## CI

`CI` runs on pull requests, pushes to `main`, and manual dispatch. It validates `VERSION`, runs the Python release-tool tests and Swift core tests with warnings treated as errors, builds the Apple Silicon app/DMG, verifies bundle signatures and DMG integrity, and checks the rendered cask with Ruby and Homebrew style. It uploads the DMG, cask, checksum manifest, and JSON metadata for seven days.

The job uses read-only repository permissions. It never registers the privileged helper, writes fan speeds, updates login items, or changes the tap. macOS runner builds validate packaging, not physical fan-control behavior across Apple Silicon models.

## One-time repository setup

- Keep `main` as the default branch. Protect it with the PR check `Test and package Apple Silicon app` once the initial PR is open.
- Add an Actions secret named `TAP_TOKEN`: a fine-grained token scoped to `tasnimzotder/homebrew-tap`, with Contents read/write permission. The default GitHub token is scoped to this repository and cannot push to the other repo. The workflow passes the token to `actions/checkout`; it is not embedded in a clone URL.
- Ensure the tap repository exists and its default branch permits this automation to push. The pipeline stages only `Casks/mac-fan-controller.rb`, preserving other casks.
- Direct public Homebrew downloads require a public application repository/release. A private repository is fine for development, but the generated release URL is not an unauthenticated public download.
- Builds are ad-hoc signed by default. Developer ID signing and Apple notarization are not implemented in this workflow. The Homebrew cask explicitly removes only `com.apple.quarantine` recursively from the installed app bundle after installation, preserving other extended attributes. This bypasses the download-quarantine warning for Homebrew installs; it does not provide Apple verification. Direct DMG installs may require approval in macOS Privacy & Security.

Permissions follow [GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) and cross-repository authentication follows [actions/checkout](https://github.com/actions/checkout).

## Release

1. Update `VERSION`, merge the app/version changes into `main`, and verify CI.
2. Remove the registered fan helper before upgrading this alpha; the helper and UI must have matching peer signatures.
3. Tag the merged commit and push the tag. For the initial version:

   ```sh
   git switch main
   git pull --ff-only
   git tag v0.1.0-alpha
   git push origin v0.1.0-alpha
   ```

`Release` has three dependent jobs:

- **Verify and build release:** the tag must exactly match `VERSION` and point to a commit reachable from `origin/main`. Run all tests, build/verify the app and DMG, generate the cask from the exact artifact, check Homebrew style, and upload release artifacts for 30 days.
- **Publish GitHub release:** verify downloaded artifact checksums, then publish the DMG, `SHA256SUMS`, `release.json`, and cask. Prerelease versions are marked as prereleases and do not become GitHub's latest stable release. Stable versions use GitHub's normal latest-release selection.
- **Update Homebrew tap:** checkout the tap with `TAP_TOKEN`, download the actual published DMG, compare its SHA256 to the build and cask, validate the cask, then commit/push only that file. An unchanged cask is a successful no-op.

The build and tap jobs have read-only source-repository permissions; only the publication job receives Contents write permission. Release runs for the same tag cannot overlap, and tap writes are serialized. A manual workflow dispatch accepts an existing release tag for recovery, using the source and VERSION at that tag.

## Failure recovery

- If build/tests/validation fail, no release or tap update happens. Correct the issue before tagging a release commit. Avoid moving an already published tag.
- If publication fails before creating a release, rerun that failed job using the retained artifacts.
- If a release was created but the job failed afterward, inspect the published release and its assets before retrying. `gh release create` intentionally fails if the release already exists, instead of replacing public assets silently.
- If the tap job fails (including a missing token), the GitHub release remains available. Configure/fix the token or tap policy, then rerun **only the failed tap job**. It reuses the original artifacts and verifies the public DMG before writing.
- To use updated workflow logic for an already published release, dispatch `Release` with its tag and `tap_only=true`. This skips building and publication, verifies the published DMG against its metadata, manifest, and cask, and updates only the tap. It preserves the release assets and normalizes the older equivalent Ventura dependency syntax.
- Rebuilding a DMG can produce a different checksum. Do not replace a published asset under the same tag with a fresh build while retaining the old cask.

To regenerate metadata locally:

```sh
make dmg
python3 tools/release-metadata.py --tag v0.1.0-alpha --repository tasnimzotder/mac-fan-controller
ruby -c dist/mac-fan-controller.rb
HOMEBREW_NO_AUTO_UPDATE=1 brew style dist/mac-fan-controller.rb
```

No GitHub release, version tag, or Homebrew tap update is performed merely by committing these workflows.
