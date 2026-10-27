# Troubleshooting

Start with the log: **Open Log** in the menu, or `~/Library/Logs/IPTether/iptether.log`. Every
run starts with a `public IP = …` line and ends with `done.` or `done, with N failure(s)`.

## The menu shows a warning

The warning icon and the line under the status show the latest run's result.

| Message | Meaning | What to do |
|---|---|---|
| Some firewalls failed. See the log. | The run finished, but at least one cloud call failed (exit code 1) | Find the `failed` lines in the log; the error text from AWS or Azure is just above each one |
| Skipped. Another sync was running or the IP changed. | Exit code 75 | Nothing. The next run catches up |
| The sync engine failed (code N). | The engine didn't run properly | Check the end of the log; reinstall the app if the engine is missing |
| config.json could not be read… | The settings file isn't valid JSON | Fix or delete `~/Library/Application Support/IPTether/config.json`. Deleting it brings back first-run defaults |

## Log messages

| Log line | Meaning | Fix |
|---|---|---|
| `aws CLI not found, skipping AWS` / `az CLI not found…` | The CLI isn't in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` or `/bin` | `brew install awscli` / `brew install azure-cli`, or turn that cloud off in Settings → Clouds |
| `AWS: cannot list regions (auth?), skipping AWS` | The AWS CLI isn't signed in, or the session expired | `aws configure`, or `aws sso login --profile <profile>` |
| `Azure: cannot list subscriptions (az login?)` | The Azure CLI isn't signed in | `az login` |
| `Azure <subscription>: cannot list NSGs (sign in to its tenant?)` | That subscription belongs to a tenant you haven't signed in to | `az login --tenant <tenant-id>`, or remove the subscription from Settings |
| `… add failed` / `… update failed` / `… remove failed` | AWS or Azure refused the change, often a missing permission | See [permissions](permissions.md); the exact error is just above the line |
| `… already allowed by another rule ("…"); not adding` | Someone else's rule already allows your IP | Nothing. IPTether never touches other rules |
| `… production, not managed` | The firewall looks like production | Expected. Add it to the allow list if you really want it managed ([configuration](configuration.md#prod)) |
| `public IP changed during run (…); aborting` | Your IP changed mid-run (network switch, VPN) | Nothing. The next run applies the new IP |
| `cannot re-verify public IP; aborting` | The IP lookup services weren't reachable mid-run | Check your connection; the next run retries |
| `ERROR: could not determine public IP` | None of the IP lookup services answered | Check your connection, a proxy, or a firewall blocking them. You can change the services in Settings → Advanced |
| `ignoring IP lookup service "…": only https:// URLs are used` | An entry in `ipServices` isn't `https://` | Change it to `https://`, or remove it |
| `ERROR: no https:// IP lookup services in ipServices` | No usable service is configured | Settings → Advanced → Restore Defaults |
| `another sync is running (pid N); skipping` | A run was already writing | Nothing. If it repeats for more than an hour, the lock is taken over as stale automatically |
| `taking over stale lock` | A previous run died while holding the lock | Nothing |

## Other questions

**IPTether didn't add my IP to a firewall I expected.** It only manages firewalls that already
allow SSH (see [known limitations](architecture.md#known-limitations)), skips production, and
skips AWS groups where another rule already allows your IP. Run **Preview Changes** to see what it
finds.

**My IP changed but nothing happened.** Check that Automatic Updates is on. Without it, IPTether
only syncs when you ask.

**Two Macs keep changing each other's rule.** They share a tag. Give each Mac its own tag
(Settings → General), after running "Remove My IP" on one of them.

**I want to remove IPTether completely.**

1. Choose **Remove My IP** and wait for it to finish.
2. Turn off **Open at login** in Settings, and quit.
3. Delete the app, `~/Library/Application Support/IPTether` and `~/Library/Logs/IPTether`.
