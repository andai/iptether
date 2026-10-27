# Configuration

IPTether keeps its settings in `~/Library/Application Support/IPTether/config.json`. The Settings
window edits it. You can also edit it by hand; the app reads it again when it next starts, and the
engine reads it on every run.

Every key is optional. A missing key uses the default below, and unknown keys are ignored. A file
that isn't valid JSON, or has a `version` other than `1`, stops the engine before it contacts any
cloud.

## Example

```json
{
  "version": 1,
  "tag": "jane-macbook",
  "port": 22,
  "aws": { "enabled": true, "regions": [] },
  "azure": { "enabled": true, "subscriptions": [] },
  "prod": {
    "exclude": true,
    "namePattern": "prod",
    "tagKeys": ["env", "environment"],
    "tagValues": ["prod", "production"],
    "allow": []
  },
  "ipServices": [
    "https://checkip.amazonaws.com",
    "https://ifconfig.me",
    "https://api.ipify.org"
  ],
  "schedule": {
    "automatic": false,
    "intervalSeconds": 180,
    "syncOnNetworkChange": true,
    "dailySweep": "09:30"
  }
}
```

The same file is in [`engine/config.example.json`](../engine/config.example.json).

## Reference

### General

| Key | Default | Meaning |
|---|---|---|
| `version` | `1` | Format version. Must be `1` |
| `tag` | `<user>-<host>` | Identifies this Mac's rules: AWS description `ssh-autosync:<tag>`, Azure rule `ssh-autosync-<tag>`. Letters, digits, `.`, `_` and `-` only. The default is your user name and short host name, lowercased, with other characters turned into `-` |
| `port` | `22` | The SSH port to look for and to open (1–65535) |

**Changing the tag** makes IPTether create new rules. Rules under the old tag stay behind. Run
"Remove My IP" (`--remove`) before you change it.

### `aws`

| Key | Default | Meaning |
|---|---|---|
| `aws.enabled` | `true` | Manage AWS security groups |
| `aws.regions` | `[]` | Regions to check, such as `["eu-west-1"]`. Empty means every region enabled for the account |

### `azure`

| Key | Default | Meaning |
|---|---|---|
| `azure.enabled` | `true` | Manage Azure network security groups |
| `azure.subscriptions` | `[]` | Subscription IDs to check. Empty means every enabled subscription the `az` login can see |

### `prod`

| Key | Default | Meaning |
|---|---|---|
| `prod.exclude` | `true` | Leave production firewalls alone |
| `prod.namePattern` | `"prod"` | Extended regular expression matched against the firewall name, ignoring case. Note that `"prod"` also matches `pre-prod` and `products` |
| `prod.tagKeys` | `["env", "environment"]` | Tag names to look at, ignoring case |
| `prod.tagValues` | `["prod", "production"]` | Values of those tags that mean production, ignoring case |
| `prod.allow` | `[]` | Firewalls to manage even though they look like production: AWS security group names or IDs, Azure NSG names, or `resource-group/nsg-name` |

On a production firewall IPTether adds nothing, and removes its own rule if it finds one.

### `ipServices`

| Key | Default | Meaning |
|---|---|---|
| `ipServices` | `checkip.amazonaws.com`, `ifconfig.me`, `api.ipify.org` (all `https://`) | Services that answer with your public IP as plain text, tried in order until one gives a valid IPv4 address |

Only `https://` addresses are used. The engine skips any other entry and logs it, so nobody on your local network can hand IPTether a fake IP. If no `https://` service is left, the run stops with exit code 1. The services you list see your public IP each time IPTether checks it. You can point this at a service you run yourself.

### `schedule` (used by the app; the engine ignores it)

| Key | Default | Meaning |
|---|---|---|
| `schedule.automatic` | `false` | Sync automatically. Off until you turn it on after a preview |
| `schedule.intervalSeconds` | `180` | How often to check whether the IP changed. At least `60` |
| `schedule.syncOnNetworkChange` | `true` | Sync 5 seconds after the network changes (Wi-Fi, VPN, tethering) |
| `schedule.dailySweep` | `"09:30"` | Local time `HH:mm` for a daily full sweep, which catches new firewalls. `null` turns it off |

## Running the engine with another file

The engine reads `IPTETHER_CONFIG` if it's set:

```bash
IPTETHER_CONFIG=~/work-config.json engine/iptether-sync.sh --dry-run
```
