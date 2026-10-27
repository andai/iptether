# Development

## Requirements

- macOS 14 or later.
- Xcode, or the Xcode Command Line Tools (see below).
- To try real syncs: the AWS and/or Azure CLI, signed in. The tests don't need either.

## Build, test, run

```bash
scripts/test.sh          # Swift tests, then the engine tests
scripts/build-app.sh     # universal, ad-hoc signed build/IPTether.app
open build/IPTether.app
```

`build-app.sh` takes `VERSION`, `BUNDLE_ID` and `SIGN_IDENTITY` from the environment; see the top
of the script.

To run the app straight from SwiftPM while you work, point it at the engine in your checkout:

```bash
IPTETHER_ENGINE="$PWD/engine/iptether-sync.sh" swift run IPTether
```

With only the Command Line Tools, add
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` in front (see below).

To try the engine without touching real files or firewalls:

```bash
IPTETHER_STATE_DIR=/tmp/ipt IPTETHER_LOG=/tmp/ipt/log engine/iptether-sync.sh --dry-run
```

### With only the Command Line Tools

The scripts work around two problems when Xcode isn't installed:

1. **SDK.** The macOS 27 SDK's SwiftUI uses macro plugins that ship only with Xcode. The scripts
   build against the macOS 26 SDK the Command Line Tools also include.
2. **Swift Testing.** Once `SDKROOT` is set, SwiftPM doesn't find Swift Testing's macro plugin, so
   `test.sh` passes `-plugin-path` itself.

With full Xcode, plain `swift build` and `swift test` work too.

## Repository layout

| Path | Contents |
|---|---|
| `Sources/IPTetherCore/` | **Testable logic, no UI.** `Config.swift` (the `config.json` model; every key optional), `ConfigStore.swift` (file locations, load/save), `Engine.swift` (runs the engine, maps exit codes, parses previews, finds the CLIs), `Schedule.swift` (daily sweep time) |
| `Sources/IPTether/` | **The app.** `AppModel.swift` (state and all scheduling), `MenuContent.swift`, `SettingsView.swift`, `PreviewView.swift`, `IPTetherApp.swift` |
| `Tests/IPTetherCoreTests/` | Swift tests. `EngineTests` also runs the real engine against stub CLIs |
| `engine/iptether-sync.sh` | The sync engine ([architecture](architecture.md)) |
| `engine/tests/run-tests.sh` | Engine tests with stub `aws`, `az` and `curl`, under macOS's bash 3.2 |
| `permissions/` | Least-privilege AWS and Azure templates ([permissions](permissions.md)) |
| `scripts/` | `test.sh`, `build-app.sh` |
| `.github/` | CI, the DCO check, issue and PR templates, CODEOWNERS |

## Rules that keep IPTether safe

- The engine **never touches a rule without IPTether's marker**. Every new code path that writes
  must find its target the same way the existing ones do.
- Every write goes through `mutate` (which calls `run`). That's what makes `--dry-run`, the IP
  re-check before writing, and failure counting work.
- The engine must keep running on the bash 3.2 that ships with macOS, with no tools beyond what
  macOS includes plus the cloud CLIs. Config is read with `plutil`, not `jq`.
- The app and the engine meet only at `config.json` and the engine's exit codes. If you add a
  setting, update `Config.swift`, the engine if it reads it, and
  [configuration.md](configuration.md).

## Adding a cloud provider

A provider is a new section of the engine plus its settings. Open an issue first to agree the
design.

1. **Engine:** add `sync_<provider>()` next to `sync_aws` and `sync_azure`, and call it at the end
   of the script. It should:
   - find firewalls that already allow the SSH port;
   - find IPTether's own rule by the marker;
   - send every write through `mutate`, with an "already done" pattern for that provider's
     duplicate and not-found errors;
   - apply `is_prod` and honor `REMOVE`.
2. **Config:** add a `<provider>` section (at least `enabled`) to `Config.swift`, with defaults,
   and read it in the engine with `cfg` / `cfg_list`.
3. **App:** add a section to Settings → Clouds, and to `Discovery` if it can list accounts or
   projects.
4. **Tests:** add a stub CLI and cases to `engine/tests/run-tests.sh`, covering add, stale-rule
   removal, production, `--remove` and `--dry-run`.
5. **Permissions:** add a minimal template to `permissions/`, and document it in
   [permissions.md](permissions.md).
