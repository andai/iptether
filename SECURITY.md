# Security Policy

IPTether changes firewall rules on your cloud accounts, so we take security reports seriously and
handle them privately.

## Supported versions

Security fixes go into the latest release only. Please update before reporting.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

**Please don't open a public issue, discussion or pull request for a security problem.**

Report it privately through GitHub:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the problem, how to reproduce it, and what an attacker could do with it.

Remove real account IDs, subscription IDs, IP addresses and firewall names from logs before you
attach them.

## What to expect

| Step | Target |
|---|---|
| We acknowledge your report | within 3 business days |
| We confirm the problem and its severity, or explain why it isn't one | within 10 business days |
| We release a fix and publish an advisory | as soon as practical; we'll agree a date with you |

We'll keep you updated in the private advisory, and credit you in the advisory and release notes
unless you'd rather stay anonymous.

## Scope

In scope:

- The sync engine (`engine/iptether-sync.sh`): for example, changing rules it doesn't own,
  writing an IP that isn't yours, or skipping the production exclusion.
- The app (`Sources/`): for example, running unexpected commands or writing outside its own
  folders.
- The permission templates (`permissions/`): anything broader than the engine needs.
- The build and release scripts and workflows.

Out of scope:

- Vulnerabilities in the AWS CLI, Azure CLI, macOS or the IP lookup services. Report those to
  their owners.
- Problems that need an attacker who already controls your Mac user account.

## How IPTether limits risk

- It never sees or stores cloud credentials. It runs the `aws` and `az` CLIs with whatever account
  they're signed in to.
- It only edits rules carrying its own marker (`ssh-autosync:<tag>` on AWS,
  `ssh-autosync-<tag>` on Azure).
- It re-checks your public IP before writing and stops if the IP changed, so it can't write a stale
  address.
- The least-privilege policies in [`permissions/`](permissions/) limit what a compromised machine
  could do with the account IPTether uses.

See [docs/architecture.md](docs/architecture.md) for the details.
