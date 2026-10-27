# Architecture

IPTether has two parts with a strict split of responsibilities:

| Part | Decides | Written in |
|---|---|---|
| **The app** (`Sources/IPTether`, `Sources/IPTetherCore`) | **When** to sync, and shows the result | Swift, SwiftUI |
| **The engine** (`engine/iptether-sync.sh`) | **What** to change on which firewall | bash, using the `aws` and `az` CLIs |

They share one settings file, `config.json`. The app writes it, and the engine reads it on every
run. The engine also works on its own, so everything the app does can be scripted.

```
 menu / timer / network change / wake
                │
                ▼
   IPTether.app ── runs ──▶ iptether-sync.sh ── aws / az ──▶ AWS security groups
        │                        │                          Azure network security groups
        └─ writes config.json ───┘ reads it
                                 └─ writes last-ip, lock/, the log
```

## The engine

Each run:

1. **Finds the public IP** from the services in `ipServices`, in order: by default
   `checkip.amazonaws.com`, then `ifconfig.me`, then `api.ipify.org`, over `https://` only. If the IP matches the last one synced (`last-ip`) and this isn't a full
   sweep, the run ends here, with no cloud calls.
2. **Takes the lock** (see below).
3. **AWS:** in every enabled region (or the regions in the config), finds security groups with a
   TCP rule covering the SSH port. For each one:
   - If it's production and not on the allow list, it removes IPTether's own rule and adds nothing.
   - If another rule already allows this exact IP, it adds nothing.
   - Otherwise it adds an ingress rule for `<ip>/32` with the description `ssh-autosync:<tag>`.
   - It removes IPTether's own rules that point at an old IP.
4. **Azure:** in every enabled subscription (or the ones in the config), finds network security
   groups with an inbound Allow rule for the SSH port or `*`. For each one:
   - If it's production, it deletes IPTether's own rule.
   - Otherwise it updates the rule named `ssh-autosync-<tag>` to the new IP, or creates it at
     the highest free priority from 3999 down.
5. **Saves the IP** to `last-ip`, after checking the IP once more.

### The marker

IPTether only ever edits or deletes rules carrying its marker: the AWS rule description
`ssh-autosync:<tag>`, or the Azure rule name `ssh-autosync-<tag>`. The tag defaults to
`<user>-<host>`, so two Macs keep separate rules. This is the project's main safety guarantee, and
the tests check it.

### Production firewalls

A firewall counts as production if its name matches `prod.namePattern`, or one of its tags in
`prod.tagKeys` has a value in `prod.tagValues`. Matching ignores case. Unless the firewall is in
`prod.allow`, IPTether adds nothing there and removes its own rule if it finds one. `--remove`
ignores this check and removes IPTether's rules everywhere.

### Never writing the wrong IP

- **Lock.** Only one run writes at a time. The lock is a folder (`lock/`), because `mkdir` is
  atomic and macOS has no `flock`. A second run exits with code 75. A lock counts as stale, and is
  taken over, when the process holding it has exited or the lock is more than an hour old.
- **IP re-check.** Before each write, the engine fetches the public IP again: at most once every
  60 seconds, and always after a gap, such as the Mac sleeping mid-run. If the IP changed, or
  can't be confirmed, the run stops with exit code 75 without saving `last-ip`, and the next run
  applies the new IP.

### Modes and exit codes

| Command | Does |
|---|---|
| `iptether-sync.sh` | Syncs only if the public IP changed since the last sync |
| `iptether-sync.sh --full` | Checks every firewall even if the IP didn't change |
| `iptether-sync.sh --dry-run` | Prints the commands it would run (`DRY:` lines) and changes nothing. Takes no lock |
| `iptether-sync.sh --remove` | Removes IPTether's own rules everywhere, including production |

| Exit code | Meaning |
|---|---|
| 0 | Done |
| 1 | Finished, but at least one cloud call failed (details in the log). Also used for an unreadable config or no public IP |
| 2 | Unknown command-line option |
| 75 | Skipped: another run held the lock, or the IP changed during the run. The next run catches up |

### Known limitations

- IPv4 only.
- On AWS, a security group counts as "allowing SSH" only through a TCP rule. A rule allowing all
  traffic (protocol `-1`) isn't detected.
- On Azure, a port range such as `20-25` isn't matched, only `22`, `*` or a list containing `22`.

## The app

- **Menu bar only.** It has no Dock icon (`LSUIElement`).
- **Scheduling** runs only while **Automatic Updates** is on:
  - every 1, 3, 5, 15 or 30 minutes (minimum 60 seconds);
  - 5 seconds after the network changes (`NWPathMonitor`);
  - when the Mac wakes;
  - a daily full sweep at the set time, which runs straight after wake if it was missed during
    sleep.
- **First launch** writes a config with Automatic Updates off and opens the Preview window by
  itself, which starts a dry run straight away. The dry run only reads. The window shows counts and
  the full output, and nothing is written to a firewall until you apply. Until then the menu also
  offers "Set Up IPTether…" to reopen it.
- **Remove My IP** turns Automatic Updates off first, then runs `--remove`, so a scheduled run
  can't add the IP back.
- **Finding the CLIs.** The engine runs with `PATH` set to
  `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, because apps started by macOS
  don't get your shell's `PATH`.

## Files

| Path | What |
|---|---|
| `~/Library/Application Support/IPTether/config.json` | Settings ([reference](configuration.md)) |
| `~/Library/Application Support/IPTether/last-ip` | The last IP synced successfully |
| `~/Library/Application Support/IPTether/lock/` | Present only while a run is writing |
| `~/Library/Application Support/IPTether/last-error` | Error output of the most recent failed cloud call |
| `~/Library/Logs/IPTether/iptether.log` | Every run and every change |

The engine takes these paths from `IPTETHER_STATE_DIR`, `IPTETHER_CONFIG` and `IPTETHER_LOG` when
they're set. The tests use them to run against a temporary folder.
