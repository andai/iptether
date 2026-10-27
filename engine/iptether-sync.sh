#!/usr/bin/env bash
#
# iptether-sync.sh — the IPTether sync engine. Keeps port-22 access pointed at THIS
# machine's current public IP, across every AWS security group and Azure NSG that
# already allows SSH. The IPTether app runs it; it also works on its own.
#
# Append-safe: it manages ONLY its own marked entry on each firewall.
#   - AWS   : an ingress rule whose Description is  "ssh-autosync:<TAG>"
#   - Azure : an inbound rule named               "ssh-autosync-<TAG>"
# It never edits or deletes anyone else's rule. On an IP change it adds the new
# entry and removes only the previous entry carrying its own marker. If another
# rule already allows this IP on an AWS group, it adds nothing there.
#
# Production firewalls are left out by default: a firewall counts as production
# when its name matches prod.namePattern or one of its env tags says prod. The
# script adds nothing there and removes its own entry if it finds one. List a
# firewall's name or id in prod.allow to manage it anyway.
#
# Settings come from config.json in the state folder (see config.example.json).
# Without that file the built-in defaults below apply: the tag is "<user>-<host>",
# and every AWS region and every enabled Azure subscription you can see is covered.
#
# Uses the aws/az CLIs exactly as already logged in. Nothing is replaced.
#
# Usage:
#   iptether-sync.sh            # sync if the public IP changed since last run
#   iptether-sync.sh --full     # sync every firewall even if the IP is unchanged
#   iptether-sync.sh --dry-run  # show what would change, make NO changes
#   iptether-sync.sh --remove   # remove ONLY my own marked entries everywhere (rollback)
#
# Whoever schedules runs (the app, cron) must stop scheduling after --remove,
# or the next run adds the IP back.
#
# Only one run writes at a time (lock dir in STATE_DIR). A run that is already
# going makes later runs exit 75. While writing, the public IP is re-checked
# (at most every RECHECK_SECS, and always after a sleep gap). If it changed, the
# run aborts without saving state, so a run that slept can't write an old IP.
#
# Exit codes: 0 ok · 1 no IP, bad config, or some firewall calls failed ·
#             75 skipped (another run holds the lock, or the IP changed mid-run)
#
set -uo pipefail
shopt -s nocasematch   # name, tag and allow-list matches ignore case

# ----------------------------- paths ---------------------------------------
STATE_DIR="${IPTETHER_STATE_DIR:-${HOME}/Library/Application Support/IPTether}"
CONFIG_FILE="${IPTETHER_CONFIG:-${STATE_DIR}/config.json}"
STATE_FILE="${STATE_DIR}/last-ip"
LOG_FILE="${IPTETHER_LOG:-${HOME}/Library/Logs/IPTether/iptether.log}"
ERR_FILE="${STATE_DIR}/last-error"              # stderr of the latest cloud write
LOCK_DIR="${STATE_DIR}/lock"
LOCK_MAX_AGE=3600                               # a lock older than this is treated as stale
RECHECK_SECS=60                                 # re-verify the public IP at most this often
# ---------------------------------------------------------------------------

DRY=0; FULL=0; REMOVE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --full)    FULL=1 ;;
    --remove)  REMOVE=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"
exec 3>&1   # the caller's stdout, for DRY lines (cloud calls send their own stdout to /dev/null)
FAILS=0
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
run() { # run a mutating command, or just print it in dry-run
  if [ "$DRY" = 1 ]; then echo "    DRY: $*" >&3; return 0; fi
  # never write an IP that is no longer ours (--remove deletes regardless of IP)
  [ "$REMOVE" = 1 ] || ip_still_current || exit 75
  "$@"
}

# mutate <what> <already-done regex> cmd... — run a cloud write. If it fails with an
# error matching the regex (a duplicate add, a rule that is already gone), the work
# is already done, so it counts as success. Any other failure is logged and counted.
mutate() {
  local what="$1" done_re="$2"; shift 2
  if run "$@" </dev/null >/dev/null 2>"$ERR_FILE"; then return 0; fi
  cat "$ERR_FILE" >> "$LOG_FILE"
  if [ -n "$done_re" ] && grep -qE "$done_re" "$ERR_FILE"; then
    log "${what}: already done"
    return 0
  fi
  log "${what} failed"
  FAILS=$((FAILS + 1))
  return 1
}

# ----------------------------- config --------------------------------------
cfg() { # cfg <keypath> [default] — one value from CONFIG_FILE (plutil reads JSON)
  local v
  if [ -f "$CONFIG_FILE" ] && v="$(plutil -extract "$1" raw -o - "$CONFIG_FILE" 2>/dev/null)"; then
    echo "$v"
  else
    echo "${2:-}"
  fi
}
cfg_list() { # cfg_list <keypath> [default...] — array items one per line; defaults if the key is absent
  local key="$1" n i=0; shift
  if [ ! -f "$CONFIG_FILE" ] || [ "$(plutil -type "$key" "$CONFIG_FILE" 2>/dev/null)" != array ]; then
    [ $# -gt 0 ] && printf '%s\n' "$@"
    return 0
  fi
  n="$(cfg "$key" 0)"
  while [ "$i" -lt "$n" ]; do cfg "${key}.${i}"; i=$((i + 1)); done
}

if [ -f "$CONFIG_FILE" ] && [ "$(cfg version)" != 1 ]; then
  log "ERROR: ${CONFIG_FILE} is not valid JSON or has an unsupported version (need \"version\": 1)"
  exit 1
fi
# "<user>-<host>", lowercased, with anything outside [a-z0-9._-] turned into "-"
DEFAULT_TAG="$(printf '%s-%s' "$(id -un)" "$(hostname -s)" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')"
TAG="$(cfg tag "$DEFAULT_TAG")"                      # identifies MY entries
PORT="$(cfg port 22)"
AWS_ENABLED="$(cfg aws.enabled true)"
AWS_REGIONS="$(cfg_list aws.regions)"                # empty = every enabled region
AZ_ENABLED="$(cfg azure.enabled true)"
AZ_SUBSCRIPTIONS="$(cfg_list azure.subscriptions)"   # empty = every enabled subscription
PROD_EXCLUDE="$(cfg prod.exclude true)"
PROD_PATTERN="$(cfg prod.namePattern prod)"          # extended regex, case-insensitive
PROD_TAG_KEYS="$(cfg_list prod.tagKeys env environment)"
PROD_TAG_VALUES="$(cfg_list prod.tagValues prod production)"
PROD_ALLOW="$(cfg_list prod.allow)"                  # firewall names/ids managed even if prod

# Services that answer with the caller's public IP as plain text, tried in order. Only
# https:// ones are used, so nobody on the local network can feed the engine a fake IP.
IP_SERVICES=()
while IFS= read -r svc; do
  case "$svc" in
    "") ;;
    https://*) IP_SERVICES+=("$svc") ;;
    *) log "ignoring IP lookup service \"${svc}\": only https:// URLs are used" ;;
  esac
done <<< "$(cfg_list ipServices https://checkip.amazonaws.com https://ifconfig.me https://api.ipify.org)"

[[ "$TAG" =~ ^[A-Za-z0-9._-]+$ ]] || { log "ERROR: tag \"${TAG}\" may only use letters, digits, . _ -"; exit 1; }
[[ "$PORT" =~ ^[0-9]+$ ]]         || { log "ERROR: port \"${PORT}\" is not a number"; exit 1; }
[ "${#IP_SERVICES[@]}" -gt 0 ]    || { log "ERROR: no https:// IP lookup services in ipServices"; exit 1; }
AWS_DESC="ssh-autosync:${TAG}"
AZ_RULE="ssh-autosync-${TAG}"

# is_prod <id> <name> <k=v;k=v> — true if the firewall counts as production and is
# not in prod.allow, so this script must not keep an entry on it
is_prod() {
  local id="$1" name="$2" tags="$3" a pair k v key val
  local -a pairs
  [ "$PROD_EXCLUDE" = true ] || return 1
  for a in $PROD_ALLOW; do [[ "$a" == "$id" || "$a" == "$name" ]] && return 1; done
  [ -n "$PROD_PATTERN" ] && [[ "$name" =~ $PROD_PATTERN ]] && return 0
  IFS=';' read -r -a pairs <<< "$tags"
  for pair in "${pairs[@]:-}"; do
    k="${pair%%=*}"; v="${pair#*=}"
    for key in $PROD_TAG_KEYS; do
      [[ "$k" == "$key" ]] || continue
      for val in $PROD_TAG_VALUES; do [[ "$v" == "$val" ]] && return 0; done
    done
  done
  return 1
}

# ----------------------------- current IP ----------------------------------
fetch_ip() { # print the current public IP, or fail
  local svc ip
  for svc in "${IP_SERVICES[@]}"; do
    ip="$(curl -fsS --max-time 10 "$svc" 2>/dev/null | tr -d '[:space:]')" || ip=""
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && { echo "$ip"; return 0; }
  done
  return 1
}

ip_still_current() { # re-fetch the IP if RECHECK_SECS passed (or "force"); fail if it moved
  local now ip
  now="$(date +%s)"
  if [ "${1:-}" != force ] && [ $((now - IP_CHECKED_AT)) -lt "$RECHECK_SECS" ]; then
    return 0
  fi
  if ! ip="$(fetch_ip)"; then
    log "cannot re-verify public IP; aborting before any further writes"
    return 1
  fi
  IP_CHECKED_AT="$now"
  if [ "${ip}/32" != "$CIDR" ]; then
    log "public IP changed during run (${CIDR} -> ${ip}/32); aborting, next run will apply it"
    return 1
  fi
  return 0
}

IP="$(fetch_ip)" || { log "ERROR: could not determine public IP"; exit 1; }
IP_CHECKED_AT="$(date +%s)"
CIDR="${IP}/32"

LAST=""; [ -f "$STATE_FILE" ] && LAST="$(cat "$STATE_FILE")"
if [ "$CIDR" = "$LAST" ] && [ "$FULL" = 0 ] && [ "$DRY" = 0 ] && [ "$REMOVE" = 0 ]; then
  exit 0   # unchanged — do nothing, cheaply
fi

# ----------------------------- lock ----------------------------------------
# mkdir is atomic, so it works as a lock without flock (not on stock macOS).
# A lock is stale when its owner has exited, or when it is older than LOCK_MAX_AGE.
acquire_lock() {
  local holder age
  if mkdir "$LOCK_DIR" 2>/dev/null; then echo $$ > "$LOCK_DIR/pid"; return 0; fi
  holder="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
  if [ "$age" -lt "$LOCK_MAX_AGE" ] && { [ -z "$holder" ] || kill -0 "$holder" 2>/dev/null; }; then
    return 1   # held by a live run (or one that is still writing its pid)
  fi
  log "taking over stale lock (pid ${holder:-?}, ${age}s old)"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || return 1
  echo $$ > "$LOCK_DIR/pid"
}
release_lock() { # only remove the lock if it is still ours
  [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK_DIR"
}

if [ "$DRY" = 0 ]; then
  if ! acquire_lock; then
    log "another sync is running (pid $(cat "$LOCK_DIR/pid" 2>/dev/null || echo '?')); skipping"
    exit 75
  fi
  trap release_lock EXIT
fi

log "public IP = ${CIDR} (was: ${LAST:-none})  dry=${DRY} full=${FULL} remove=${REMOVE}"

# =============================== AWS =======================================
sync_aws() {
  [ "$AWS_ENABLED" = true ] || { log "AWS disabled in config, skipping"; return; }
  command -v aws >/dev/null 2>&1 || { log "aws CLI not found, skipping AWS"; return; }
  local regions r sgs sg name tags rules rid cidr desc mine have_current covered managed what
  regions="$AWS_REGIONS"
  if [ -z "$regions" ]; then
    regions="$(aws ec2 describe-regions --region us-east-1 \
                --query 'Regions[].RegionName' --output text 2>/dev/null </dev/null)" || {
      log "AWS: cannot list regions (auth?), skipping AWS"; FAILS=$((FAILS + 1)); return; }
  fi

  for r in $regions; do
    # SGs that already allow SSH (a rule covering the port): id, name, "k=v;k=v" tags
    sgs="$(aws ec2 describe-security-groups --region "$r" \
            --query "SecurityGroups[?IpPermissions[?FromPort<=\`${PORT}\` && ToPort>=\`${PORT}\` && IpProtocol=='tcp']].[GroupId,GroupName,join(';', Tags[].join('=', [Key,Value]) || [''])]" \
            --output text 2>/dev/null </dev/null)" || {
      log "AWS ${r}: cannot list security groups, skipping region"; FAILS=$((FAILS + 1)); continue; }
    [ -z "$sgs" ] && continue

    while IFS=$'\t' read -r sg name tags; do
      [ -z "$sg" ] && continue
      what="AWS ${r} ${sg} (${name})"
      # every IPv4 rule for exactly this port: "ruleId<TAB>cidr<TAB>description" rows
      # (bash 3.2 compatible — no mapfile)
      rules="$(aws ec2 describe-security-group-rules --region "$r" \
        --filters Name=group-id,Values="$sg" \
        --query "SecurityGroupRules[?IsEgress==\`false\` && IpProtocol=='tcp' && FromPort==\`${PORT}\` && ToPort==\`${PORT}\` && CidrIpv4!=null].[SecurityGroupRuleId,CidrIpv4,Description]" \
        --output text 2>/dev/null </dev/null)" || {
        log "${what}: cannot read rules, skipping"; FAILS=$((FAILS + 1)); continue; }

      # split into my own entries and someone else's rule that already allows this IP
      mine=""; have_current=0; covered=""
      while IFS=$'\t' read -r rid cidr desc; do
        [ -z "$rid" ] && continue
        if [ "$desc" = "$AWS_DESC" ]; then
          mine="${mine}${rid} ${cidr}"$'\n'
          [ "$cidr" = "$CIDR" ] && have_current=1
        elif [ "$cidr" = "$CIDR" ]; then
          covered="$desc"
        fi
      done <<< "$rules"

      managed=1
      if [ "$REMOVE" = 0 ] && is_prod "$sg" "$name" "$tags"; then
        managed=0
        log "${what}: production, not managed"
      fi

      if [ "$REMOVE" = 0 ] && [ "$managed" = 1 ] && [ "$have_current" = 0 ]; then
        if [ -n "$covered" ]; then
          log "${what}: ${CIDR} already allowed by another rule (\"${covered}\"); not adding"
        else
          log "${what}: add ${CIDR}"
          mutate "${what}: add" 'InvalidPermission\.Duplicate' \
            aws ec2 authorize-security-group-ingress --region "$r" --group-id "$sg" \
            --ip-permissions "IpProtocol=tcp,FromPort=${PORT},ToPort=${PORT},IpRanges=[{CidrIp=${CIDR},Description=${AWS_DESC}}]"
        fi
      fi

      # prune my own entries: all of them with --remove or on production, else only stale ones
      while read -r rid cidr; do
        [ -z "$rid" ] && continue
        if [ "$REMOVE" = 1 ] || [ "$managed" = 0 ] || [ "$cidr" != "$CIDR" ]; then
          log "${what}: remove ${cidr}"
          mutate "${what}: remove" 'InvalidSecurityGroupRuleId\.NotFound|InvalidPermission\.NotFound' \
            aws ec2 revoke-security-group-ingress --region "$r" --group-id "$sg" \
            --security-group-rule-ids "$rid"
        fi
      done <<< "$mine"
    done <<< "$sgs"
  done
}

# ============================== Azure ======================================
zip_tags() { # zip_tags "k1;k2" "v1;v2" -> "k1=v1;k2=v2"
  local IFS=';' out="" i=0
  local -a ks vs
  read -r -a ks <<< "$1"; read -r -a vs <<< "$2"
  while [ "$i" -lt "${#ks[@]}" ]; do out="${out}${ks[$i]}=${vs[$i]:-};"; i=$((i + 1)); done
  echo "$out"
}

sync_azure() {
  [ "$AZ_ENABLED" = true ] || { log "Azure disabled in config, skipping"; return; }
  command -v az >/dev/null 2>&1 || { log "az CLI not found, skipping Azure"; return; }
  local subs sub nsgs rg nsg tkeys tvals prio used managed what
  subs="$AZ_SUBSCRIPTIONS"
  if [ -z "$subs" ]; then
    subs="$(az account list --query "[?state=='Enabled'].id" -o tsv 2>/dev/null </dev/null)" || {
      log "Azure: cannot list subscriptions (az login?), skipping Azure"; FAILS=$((FAILS + 1)); return; }
    [ -z "$subs" ] && { log "Azure: no enabled subscriptions, skipping Azure"; return; }
  fi
  for sub in $subs; do
    # NSGs that already allow SSH inbound: resource group, name, tag keys, tag values
    nsgs="$(az network nsg list --subscription "$sub" \
      --query "[?securityRules[?direction=='Inbound' && access=='Allow' && (destinationPortRange=='${PORT}' || destinationPortRange=='*' || contains(destinationPortRanges, '${PORT}'))]].[resourceGroup,name,join(';', keys(tags || \`{}\`)),join(';', values(tags || \`{}\`))]" \
      -o tsv 2>/dev/null </dev/null)" || {
      log "Azure ${sub}: cannot list NSGs (sign in to its tenant?), skipping"; FAILS=$((FAILS + 1)); continue; }
    [ -z "$nsgs" ] && { log "Azure ${sub}: no SSH NSGs (or no access)"; continue; }

    while IFS=$'\t' read -r rg nsg tkeys tvals; do
      [ -z "$nsg" ] && continue
      what="Azure ${nsg}"
      # does our own rule already exist on this NSG?
      prio="$(az network nsg rule show --subscription "$sub" -g "$rg" --nsg-name "$nsg" -n "$AZ_RULE" \
               --query priority -o tsv 2>/dev/null </dev/null)"

      managed=1
      if [ "$REMOVE" = 0 ] && is_prod "${rg}/${nsg}" "$nsg" "$(zip_tags "$tkeys" "$tvals")"; then
        managed=0
        log "${what}: production, not managed"
      fi

      if [ "$REMOVE" = 1 ] || [ "$managed" = 0 ]; then
        if [ -n "$prio" ]; then
          log "${what}: remove our rule"
          mutate "${what}: remove" 'NotFound' \
            az network nsg rule delete --subscription "$sub" -g "$rg" --nsg-name "$nsg" -n "$AZ_RULE" -o none
        fi
        continue
      fi
      if [ -n "$prio" ]; then
        log "${what}: set ${CIDR} (rule exists, prio ${prio})"
        mutate "${what}: update" '' \
          az network nsg rule update --subscription "$sub" -g "$rg" --nsg-name "$nsg" -n "$AZ_RULE" \
          --source-address-prefixes "$CIDR" -o none
      else
        # pick a free priority (highest unused below 4096)
        used="$(az network nsg rule list --subscription "$sub" -g "$rg" --nsg-name "$nsg" \
                 --query "[].priority" -o tsv 2>/dev/null </dev/null)"
        prio=3999
        while echo "$used" | grep -qx "$prio"; do prio=$((prio - 1)); done
        log "${what}: create ${CIDR} (prio ${prio})"
        mutate "${what}: create" '' \
          az network nsg rule create --subscription "$sub" -g "$rg" --nsg-name "$nsg" -n "$AZ_RULE" \
          --priority "$prio" --direction Inbound --access Allow --protocol Tcp \
          --destination-port-ranges "$PORT" --source-address-prefixes "$CIDR" \
          --description "managed by IPTether for ${TAG}" -o none
      fi
    done <<< "$nsgs"
  done
}

sync_aws
sync_azure

if [ "$DRY" = 0 ]; then
  if [ "$REMOVE" = 1 ]; then
    rm -f "$STATE_FILE"
  else
    ip_still_current force || exit 75   # don't record an IP we no longer have
    echo "$CIDR" > "$STATE_FILE"
  fi
fi
if [ "$FAILS" -gt 0 ]; then
  log "done, with ${FAILS} failure(s); details above"
  exit 1
fi
log "done."
