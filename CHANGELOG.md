# Changelog

All notable changes to IPTether are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Menu bar app for macOS 14 and later.
  - Menu actions: Sync Now, Full Sweep, Preview Changes, Automatic Updates, Remove My IP,
    Open Log.
  - A status icon that shows when a sync is running or has failed.
- Preview window. It runs a dry run and lists how many rules would be added, updated or removed,
  and how many production firewalls are skipped, before anything is written.
- Settings window with General, Clouds, Production and Advanced tabs. The Clouds tab loads AWS
  regions and Azure subscriptions from the signed-in CLIs.
- Automatic updates: an interval timer, a sync when the network changes and after wake, and a
  daily full sweep. Off until you turn it on.
- Open at login.
- Sync engine (`engine/iptether-sync.sh`).
  - Keeps an SSH rule for this Mac's public IP on every AWS security group and Azure network
    security group that already allows SSH.
  - Edits only rules carrying its own marker.
  - Also runs on its own, with `--full`, `--dry-run` and `--remove`.
- `config.json` settings shared by the app and the engine; missing keys fall back to defaults.
- Production exclusion, on by default.
  - A firewall counts as production if its name matches a pattern or an `env` tag says
    `prod`/`production`.
  - IPTether adds nothing there and removes its own rule.
  - An allow list opts firewalls back in.
- Least-privilege AWS IAM policy and Azure custom role in `permissions/`.
- The Preview window opens by itself on first launch and starts a dry run. Nothing is written until
  you apply.
- `ipServices` setting, with a field in Settings → Advanced, to choose which services report your
  public IP.

### Security

- Only `https://` IP lookup services are used, so the local network can't supply a fake IP.
- Only one sync writes at a time, enforced by a lock.
- The public IP is checked again before writing; a run that slept or changed networks stops
  instead of writing an old address.
- A rule already allowing your IP under another description is left alone, not duplicated.

[Unreleased]: https://github.com/andai/iptether/commits/main
