<div align="center">

# IPTether

**Keep SSH to your cloud servers pointed at your Mac's current IP, from the menu bar.**

[![CI](https://github.com/andai/iptether/actions/workflows/ci.yml/badge.svg)](https://github.com/andai/iptether/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)

</div>

When you work from home, a café or your phone's hotspot, your public IP changes, and the SSH
rules on your AWS security groups and Azure network security groups stop matching it. IPTether
notices the change and moves your rule to the new IP everywhere. It touches nothing else.

<!-- Screenshot of the menu goes here before the first release. -->

## Features

- **Follows your IP.** It syncs on a schedule, when the network changes, after wake, and once a day
  as a full sweep.
- **Only its own rule.** It edits rules carrying its marker (`ssh-autosync:<tag>`) and nothing else.
- **Leaves production alone.** Firewalls named or tagged as production are skipped, unless you opt
  one in.
- **Preview first.** It shows exactly what it would change before anything is written, and nothing
  runs automatically until you turn it on.
- **No credentials.** It uses the `aws` and `az` CLIs you're already signed in to.
- **One-click undo.** "Remove My IP" deletes every rule it added.
- **Native and small.** A SwiftUI menu bar app (about 2 MB), universal for Apple silicon and Intel.
- **Scriptable.** The sync engine also runs on its own from Terminal.

## Requirements

- macOS 14 Sonoma or later.
- For AWS: the [AWS CLI](https://aws.amazon.com/cli/) (`brew install awscli`), signed in.
- For Azure: the [Azure CLI](https://learn.microsoft.com/cli/azure/) (`brew install azure-cli`),
  signed in.

## Installation

Signed downloads and a Homebrew cask are coming with the first release. Until then, build from
source:

```bash
git clone https://github.com/andai/iptether.git
cd iptether
scripts/build-app.sh
open build/IPTether.app
```

Building needs Xcode, or the Xcode Command Line Tools; see [development](docs/development.md).

## Quick start

1. Open IPTether. A shield appears in the menu bar.
2. The Preview window opens by itself. It checks every firewall that allows SSH and lists what it
   would change there, without changing anything.
3. Choose **Apply and Turn On Automatic Updates**.

From then on IPTether keeps your rule current. Check **Settings → Clouds** to limit it to certain
AWS regions or Azure subscriptions.

## Usage

| Menu item | What it does |
|---|---|
| **Sync Now** (⌘S) | Syncs if your IP changed since the last sync |
| **Full Sweep** (⌘F) | Checks every firewall, which picks up new servers |
| **Preview Changes…** (⌘P) | Shows what a sync would change, without changing anything |
| **Automatic Updates** | Turns scheduled syncing on or off |
| **Remove My IP…** | Removes every rule IPTether added, and turns automatic updates off |
| **Open Log** (⌘L) | Opens `~/Library/Logs/IPTether/iptether.log` |

The engine works without the app:

```bash
engine/iptether-sync.sh --dry-run   # show what would change
engine/iptether-sync.sh --full      # sync every firewall
engine/iptether-sync.sh --remove    # remove IPTether's rules everywhere
```

## Configuration

Settings live in `~/Library/Application Support/IPTether/config.json` and are edited in
**Settings**. The main ones are the tag that marks your rules, which clouds, regions and
subscriptions to cover, what counts as production, and the schedule. Every key is documented in
[docs/configuration.md](docs/configuration.md).

## Permissions

IPTether needs to list security groups and add, update or remove one inbound rule on them, and
nothing more. Ready-made least-privilege templates:

- AWS IAM policy: [`permissions/aws-iam-policy.json`](permissions/aws-iam-policy.json)
- Azure custom role: [`permissions/azure-custom-role.json`](permissions/azure-custom-role.json)

[docs/permissions.md](docs/permissions.md) explains each permission and how to apply it.

## Privacy

- **No telemetry, no analytics, no accounts.**
- IPTether contacts only:
  - AWS and Azure, through your own CLIs;
  - the IP lookup services, by default `checkip.amazonaws.com`, `ifconfig.me` and `api.ipify.org`,
    over HTTPS only. They see your public IP, as any website you visit does. You can replace them,
    for example with a service you run yourself, in Settings → Advanced.
- Everything it stores stays on your Mac: settings and state in
  `~/Library/Application Support/IPTether`, the log in `~/Library/Logs/IPTether`.

## FAQ

**Will it change or delete my other firewall rules?**
No. It only edits rules carrying its marker, `ssh-autosync:<tag>` on AWS or the rule named
`ssh-autosync-<tag>` on Azure. If another rule already allows your IP, it adds nothing.

**What happens on production servers?**
Firewalls whose name matches `prod`, or whose `env`/`environment` tag is `prod`/`production`, are
skipped, and IPTether removes its own rule from them. You can change the pattern, or allow specific
firewalls, in Settings → Production.

**How do I undo everything?**
Choose **Remove My IP…**. It deletes every rule IPTether added, including on production, and turns
off automatic updates.

**Does it store my cloud credentials?**
No. It runs the `aws` and `az` command-line tools, which use their own sign-in. IPTether never sees
keys or tokens.

**Which firewalls does it manage?**
Those that already allow SSH: AWS security groups with a TCP rule for port 22, and Azure network
security groups with an inbound Allow rule for 22. It never opens SSH where it wasn't open. See the
[known limitations](docs/architecture.md#known-limitations).

**I use two Macs. Is that OK?**
Yes. Each Mac gets its own tag (`<user>-<host>` by default), so their rules don't collide. Don't
give two Macs the same tag.

**Why isn't it in the Mac App Store?**
App Store apps must be sandboxed, and the sandbox doesn't allow running the `aws` and `az` tools.

**What if my IP changes in the middle of a sync?**
IPTether checks your IP again before writing. If it changed, the sync stops and the next one applies
the new IP, so it never writes an old address.

More answers are in [troubleshooting](docs/troubleshooting.md).

## Documentation

- [Architecture](docs/architecture.md): how the app and the engine work together.
- [Configuration](docs/configuration.md): every setting.
- [Permissions](docs/permissions.md): least-privilege AWS and Azure setup.
- [Troubleshooting](docs/troubleshooting.md): log messages and fixes.
- [Development](docs/development.md): building, testing, adding a cloud provider.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) to get started. Commits need a
DCO sign-off (`git commit -s`), and everyone taking part follows the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Please report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md), not in public
issues.

## Support

See [SUPPORT.md](SUPPORT.md) for where to ask questions and report bugs.

## License

Copyright 2026 And AI Platforms. Licensed under the [Apache License 2.0](LICENSE); see also
[NOTICE](NOTICE). The project's governance is described in [GOVERNANCE.md](GOVERNANCE.md).
