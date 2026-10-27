# Contributing to IPTether

Thanks for helping. This guide covers how to report problems, propose changes and get a pull
request merged.

By taking part you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug** with the [bug report form](../../issues/new/choose).
- **Suggest a feature** with the feature request form, or start a conversation in Discussions.
- **Improve the docs.** Fixes to `README.md` and [`docs/`](docs/) are always welcome.
- **Fix a bug or build a feature.** Look for issues labelled `good first issue` or `help wanted`.
- **Add a cloud provider.** See [Adding a cloud provider](docs/development.md#adding-a-cloud-provider).

Found a security problem? Don't open an issue. Follow [SECURITY.md](SECURITY.md) instead.

## Before you start

For anything bigger than a small fix, open an issue first and describe what you want to change.
That avoids building something we can't merge, for example a change that would let IPTether edit
rules it doesn't own.

## Development setup

You need macOS 14 or later and either Xcode or the Command Line Tools.

```bash
git clone https://github.com/andai/iptether.git
cd iptether
scripts/test.sh          # Swift tests + engine tests (no cloud access needed)
scripts/build-app.sh     # builds build/IPTether.app
```

[docs/development.md](docs/development.md) explains the repo layout, how the app and the engine
fit together, and the workarounds the scripts apply when only the Command Line Tools are installed.

## Making a change

1. Fork the repo and create a branch from `main`, named for the change
   (`fix-azure-priority`, `docs-permissions`).
2. Make your change, with tests (see below).
3. Run `scripts/test.sh` and make sure it passes.
4. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything users would notice.
5. Commit with sign-off (see below) and open a pull request against `main`.

### Commit messages

Write the subject in the imperative, under about 70 characters ("Skip NSGs tagged env=prod"). In
the body, say why the change is needed.

### Sign your commits (DCO)

We use the [Developer Certificate of Origin](https://developercertificate.org/) instead of a
contributor license agreement. Signing off certifies that you wrote the change, or otherwise have
the right to submit it under the project's license.

Add the sign-off with `-s`:

```bash
git commit -s -m "Skip NSGs tagged env=prod"
```

This adds a line like `Signed-off-by: Jane Doe <jane@example.com>`, using your git name and email.
A check on every pull request fails if a commit is missing it. To fix existing commits on your
branch:

```bash
git rebase --signoff main
git push --force-with-lease
```

## Coding guidelines

- **Match the code around you**: naming, comment density and structure.
- **Swift**: 4-space indentation; keep UI in `Sources/IPTether` and testable logic in
  `Sources/IPTetherCore`.
- **Engine** (`engine/iptether-sync.sh`):
  - It must run on the bash 3.2 that ships with macOS: no `mapfile`, no associative arrays,
    no `${var,,}`.
  - Don't add dependencies such as `jq`. The engine reads `config.json` with `plutil`.
  - **Never touch a rule without IPTether's marker.** This is the project's core safety promise.
  - Send every write through `mutate`/`run`, so dry runs, the IP re-check and failure counting
    keep working.
- **Config**: a new setting goes in `Sources/IPTetherCore/Config.swift` (decoded as optional, with
  a default), in the engine if it reads it, and in [docs/configuration.md](docs/configuration.md).

## Tests

Every behavior change needs a test:

- Logic in `IPTetherCore`: add a Swift test in `Tests/IPTetherCoreTests`.
- Engine behavior: add a case to `engine/tests/run-tests.sh`. It uses stub `aws`, `az` and `curl`
  commands, so tests never touch a real cloud. Keep it that way.

## Pull request review

- CI must pass: the tests, ShellCheck, the app build and the DCO check.
- A maintainer listed in [CODEOWNERS](.github/CODEOWNERS) must approve. Changes to `engine/` and
  `permissions/` get extra care, because they decide what IPTether is allowed to change.
- We squash or rebase on merge. Keep the pull request focused on one change.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE), the project's license.
