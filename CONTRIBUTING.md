# Contributing to Chronicle

Chronicle is a privacy-sensitive macOS automatic work log. Contributions should preserve its single-user, local-only boundary and keep activity data, window titles, notes, and usage counters off the network.

## Before opening a pull request

1. Discuss large product or data-model changes in an issue before implementation.
2. Keep unrelated changes out of the pull request.
3. Run the release preflight:

   ```sh
   ./script/run_release_preflight.sh
   ```

4. Run the unit tests documented in `README.md`.
5. For packaging, update, or release-pipeline changes, run the unsigned release dry-run:

   ```sh
   ./script/run_release_dry_run.sh
   ```

The dry-run builds and inspects a local DMG but does not sign, notarize, or upload it.

## Pull-request expectations

- Explain the user-visible outcome and privacy impact.
- Add or update tests for behavioral changes.
- Document schema, migration, export, or compatibility changes.
- Keep English and Simplified Chinese localization keys in parity.
- Never include real activity databases, window titles, notes, credentials, signing material, or diagnostics containing personal paths.

Security vulnerabilities should follow `SECURITY.md` rather than a public issue.
