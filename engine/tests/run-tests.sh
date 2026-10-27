#!/bin/bash
# Offline tests for iptether-sync.sh: stubbed curl/aws/az, throwaway state folder.
# Nothing here talks to a real cloud. Runs under macOS's /bin/bash 3.2.
#
#   engine/tests/run-tests.sh [path/to/iptether-sync.sh]
#
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$HERE/../iptether-sync.sh}"
T="$(mktemp -d "${TMPDIR:-/tmp}/iptether-tests.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
export T HOME="$T/home" PATH="$T/bin:/usr/bin:/bin"
export IPTETHER_STATE_DIR="$T/state" IPTETHER_CONFIG="$T/config.json" IPTETHER_LOG="$T/state/iptether.log"
# re-check the IP before every write, so the mid-run IP change test needs no waiting
sed 's/^RECHECK_SECS=60/RECHECK_SECS=0/' "$SRC" > "$T/sync.sh"
M="ssh-autosync:tester"
PASS=0; FAILN=0
ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
bad()  { FAILN=$((FAILN+1)); echo "  FAIL $1"; }
has()  { grep -qF -- "$2" "$1" && ok "$3" || bad "$3"; }
hasnt(){ grep -qF -- "$2" "$1" && bad "$3" || ok "$3"; }

cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
echo "$*" >> "$T/curl-calls"
cat "$T/ip"
EOF
cat > "$T/bin/aws" <<'EOF'
#!/bin/bash
echo "aws $*" >> "$T/calls"
arg() { local want="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$want" ] && { echo "$2"; return; }; shift; done; }
case "$*" in
  *describe-regions*) echo r1 ;;
  *describe-security-groups*) cat "$T/aws-sgs" ;;
  *describe-security-group-rules*)
    sg="$(arg --filters "$@")"; sg="${sg#Name=group-id,Values=}"
    n=$(grep -c describe-security-group-rules "$T/calls"); [ "$n" -ge "${FLIP_AT:-999}" ] && echo 9.9.9.9 > "$T/ip"
    cat "$T/rules-$sg" 2>/dev/null ;;
  *authorize-security-group-ingress*)
    sg="$(arg --group-id "$@")"
    [ -f "$T/dup-$sg" ] && { echo "An error occurred (InvalidPermission.Duplicate) when calling the AuthorizeSecurityGroupIngress operation" >&2; exit 254; }
    [ -f "$T/deny-$sg" ] && { echo "An error occurred (UnauthorizedOperation)" >&2; exit 254; } ;;
  *revoke-security-group-ingress*)
    rid="$(arg --security-group-rule-ids "$@")"
    [ -f "$T/gone-$rid" ] && { echo "An error occurred (InvalidSecurityGroupRuleId.NotFound) when calling the RevokeSecurityGroupIngress operation" >&2; exit 254; } ;;
esac
exit 0
EOF
cat > "$T/bin/az" <<'EOF'
#!/bin/bash
echo "az $*" >> "$T/calls"
arg() { local want="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$want" ] && { echo "$2"; return; }; shift; done; }
case "$*" in
  "account list"*) printf 'sub-one\nsub-two\n' ;;
  "network nsg list"*)
    sub="$(arg --subscription "$@")"
    [ "$sub" = bad-sub ] && { echo "ERROR: AADSTS9002313" >&2; exit 1; }
    cat "$T/az-nsgs" ;;
  "network nsg rule show"*) nsg="$(arg --nsg-name "$@")"; [ -f "$T/azrule-$nsg" ] && echo 3999 || exit 3 ;;
  "network nsg rule list"*) printf '3999\n100\n' ;;
esac
exit 0
EOF
chmod +x "$T/bin/"*

fixtures() {
  rm -rf "$T/state" "$T/calls" "$T/curl-calls" "$T"/rules-* "$T"/dup-* "$T"/gone-* "$T"/deny-* "$T"/azrule-*
  echo 1.1.1.1 > "$T/ip"; : > "$T/calls"; : > "$T/curl-calls"
  printf '%s\t%s\t%s\n' \
    sg-a app-sg "Name=app-sg" \
    sg-p shop-prod-sg "" \
    sg-t launch-wizard "Environment=Production;Owner=x" \
    sg-c covered-sg "" \
    sg-x allowed-prod-sg "" \
    sg-d dup-sg "" > "$T/aws-sgs"
  printf 'sgr-a1\t9.9.9.9/32\t%s\n' "$M" > "$T/rules-sg-a"
  printf 'sgr-p1\t1.1.1.1/32\t%s\n' "$M" > "$T/rules-sg-p"
  printf 'sgr-c1\t1.1.1.1/32\toffice ssh\nsgr-c2\t9.9.9.9/32\t%s\n' "$M" > "$T/rules-sg-c"
  touch "$T/dup-sg-d" "$T/gone-sgr-a1"
  printf 'rg1\tweb-nsg\t\t\nrg1\tdb-prod-nsg\t\t\nrg2\tchat-nsg\tenv;app\tProd;x\n' > "$T/az-nsgs"
  touch "$T/azrule-web-nsg" "$T/azrule-db-prod-nsg"
  cat > "$T/config.json" <<'EOF'
{"version":1,"tag":"tester","port":22,"aws":{"enabled":true,"regions":[]},
 "azure":{"enabled":true,"subscriptions":["good-sub","bad-sub"]},
 "prod":{"exclude":true,"namePattern":"prod","tagKeys":["env","environment"],"tagValues":["prod","production"],"allow":["allowed-prod-sg"]}}
EOF
}
LOG="$T/state/iptether.log"

echo "== 1. full sync with prod, covered, duplicate, already-gone, bad subscription"
fixtures
/bin/bash "$T/sync.sh" > "$T/out" 2>&1; rc=$?
[ $rc = 1 ] && ok "exit 1 because one subscription failed" || bad "exit was $rc"
C="$T/calls"
has  "$C" "authorize-security-group-ingress --region r1 --group-id sg-a " "adds IP to normal SG"
has  "$C" "--security-group-rule-ids sgr-a1" "prunes stale own rule"
has  "$LOG" "sg-a (app-sg): remove: already done" "already-gone rule counts as done"
hasnt "$C" "--group-id sg-p --ip-permissions" "adds nothing to prod-named SG"
has  "$C" "--security-group-rule-ids sgr-p1" "removes own rule from prod-named SG"
has  "$LOG" "sg-t (launch-wizard): production, not managed" "Environment=Production tag counts as prod"
hasnt "$C" "--group-id sg-t --ip-permissions" "adds nothing to prod-tagged SG"
has  "$LOG" "already allowed by another rule (\"office ssh\")" "covered SG logged"
hasnt "$C" "--group-id sg-c --ip-permissions" "adds nothing to covered SG"
has  "$C" "--security-group-rule-ids sgr-c2" "prunes own stale rule on covered SG"
hasnt "$C" "sgr-c1" "never touches someone else's rule"
has  "$C" "--group-id sg-x --ip-permissions" "allow list overrides prod"
has  "$LOG" "sg-d (dup-sg): add: already done" "duplicate add counts as done"
has  "$C" "nsg rule update --subscription good-sub -g rg1 --nsg-name web-nsg" "updates normal NSG"
has  "$C" "nsg rule delete --subscription good-sub -g rg1 --nsg-name db-prod-nsg" "removes own rule from prod NSG"
has  "$LOG" "Azure chat-nsg: production, not managed" "env=Prod tag on NSG counts as prod"
hasnt "$C" "--nsg-name chat-nsg -n ssh-autosync-tester --priority" "creates nothing on prod NSG"
has  "$LOG" "Azure bad-sub: cannot list NSGs" "bad subscription logged"
has  "$LOG" "done, with 1 failure(s)" "failure count reported"
[ "$(cat "$T/state/last-ip")" = 1.1.1.1/32 ] && ok "state saved" || bad "state not saved"
[ -d "$T/state/lock" ] && bad "lock left behind" || ok "lock released"

echo "== 2. --remove removes all own rules and ignores prod"
fixtures
/bin/bash "$T/sync.sh" --remove > "$T/out" 2>&1
C="$T/calls"
has  "$C" "sgr-a1" "removes own rule (normal SG)"; has "$C" "sgr-p1" "removes own rule (prod SG)"
has  "$C" "sgr-c2" "removes own rule (covered SG)"; hasnt "$C" "sgr-c1" "leaves someone else's rule"
hasnt "$C" "authorize-security-group-ingress" "adds nothing"
has  "$C" "nsg rule delete --subscription good-sub -g rg1 --nsg-name web-nsg" "deletes own NSG rule"
hasnt "$LOG" "production, not managed" "no prod classification during remove"
hasnt "$C" "launchctl" "does not touch launchd"
[ -f "$T/state/last-ip" ] && bad "state kept" || ok "state cleared"

echo "== 3. --dry-run prints commands, writes nothing"
fixtures
/bin/bash "$T/sync.sh" --dry-run > "$T/out" 2>&1
has  "$T/out" "DRY: aws ec2 authorize-security-group-ingress --region r1 --group-id sg-a" "DRY line on stdout"
has  "$T/out" "DRY: az network nsg rule delete" "DRY line for Azure"
grep -qE 'authorize-security|revoke-security|nsg rule (update|create|delete)' "$T/calls" && bad "a write ran" || ok "no write ran"
[ -f "$T/state/last-ip" ] && bad "state written" || ok "no state written"

echo "== 4. no config file: user-host tag, every subscription, prod excluded"
fixtures; rm "$T/config.json"
/bin/bash "$T/sync.sh" > "$T/out" 2>&1
want="$(printf '%s-%s' "$(id -un)" "$(hostname -s)" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')"
has "$T/calls" "Description=ssh-autosync:${want}" "default tag is <user>-<host>"
has "$T/calls" "az account list" "asks az for subscriptions"
has "$T/calls" "nsg list --subscription sub-one" "covers first subscription"
has "$T/calls" "nsg list --subscription sub-two" "covers second subscription"
has "$LOG" "production, not managed" "prod excluded by default"
hasnt "$T/calls" "--group-id sg-x --ip-permissions" "no allow list by default"

echo "== 5. broken config stops the run"
fixtures; echo '{ not json' > "$T/config.json"
/bin/bash "$T/sync.sh" > "$T/out" 2>&1; rc=$?
[ $rc = 1 ] && ok "exit 1" || bad "exit was $rc"
[ -s "$T/calls" ] && bad "cloud called" || ok "no cloud calls"

echo "== 6. prod exclusion off + aws disabled"
fixtures
cat > "$T/config.json" <<'EOF'
{"version":1,"tag":"tester","aws":{"enabled":false},"azure":{"subscriptions":["good-sub"]},"prod":{"exclude":false}}
EOF
/bin/bash "$T/sync.sh" > "$T/out" 2>&1; rc=$?
[ $rc = 0 ] && ok "exit 0" || bad "exit was $rc"
hasnt "$T/calls" "aws " "AWS skipped"
has "$T/calls" "nsg rule update --subscription good-sub -g rg1 --nsg-name db-prod-nsg" "prod NSG managed when exclusion off"

echo "== 7. real AWS failure is counted"
fixtures; touch "$T/deny-sg-a"
/bin/bash "$T/sync.sh" > "$T/out" 2>&1
has "$LOG" "sg-a (app-sg): add failed" "add failure logged"
has "$LOG" "UnauthorizedOperation" "AWS error text kept in log"

echo "== 8. lock held -> 75; IP change mid-run -> 75, no state"
fixtures; mkdir -p "$T/state/lock"; sleep 30 & echo $! > "$T/state/lock/pid"; LP=$!
/bin/bash "$T/sync.sh" > "$T/out" 2>&1; rc=$?; kill $LP; wait $LP 2>/dev/null
[ $rc = 75 ] && ok "held lock -> 75" || bad "exit was $rc"
fixtures; FLIP_AT=2 /bin/bash "$T/sync.sh" > "$T/out" 2>&1; rc=$?
[ $rc = 75 ] && ok "IP change -> 75" || bad "exit was $rc"
[ -f "$T/state/last-ip" ] && bad "state written" || ok "no state written"

echo "== 9. unchanged IP exits early"
fixtures; mkdir -p "$T/state"; echo 1.1.1.1/32 > "$T/state/last-ip"
/bin/bash "$T/sync.sh" > "$T/out" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -s "$T/calls" ] && ok "no calls, exit 0" || bad "rc=$rc calls=$(wc -l < "$T/calls")"

echo "== 10. ipServices: default list, configured list, http:// ignored"
fixtures
/bin/bash "$T/sync.sh" > "$T/out" 2>&1
has "$T/curl-calls" "https://checkip.amazonaws.com" "default service used"
fixtures
cat > "$T/config.json" <<'EOF'
{"version":1,"tag":"tester","aws":{"enabled":false},"azure":{"enabled":false},
 "ipServices":["http://insecure.test","https://ip.example.test"]}
EOF
/bin/bash "$T/sync.sh" > "$T/out" 2>&1; rc=$?
[ $rc = 0 ] && ok "exit 0" || bad "exit was $rc"
has   "$T/curl-calls" "https://ip.example.test" "configured https service used"
hasnt "$T/curl-calls" "insecure.test" "http:// service never called"
hasnt "$T/curl-calls" "checkip.amazonaws.com" "defaults replaced by the configured list"
has   "$LOG" 'ignoring IP lookup service "http://insecure.test"' "http:// service logged as ignored"

echo "== 11. no https:// service stops the run"
fixtures
cat > "$T/config.json" <<'EOF'
{"version":1,"tag":"tester","ipServices":["http://insecure.test"]}
EOF
/bin/bash "$T/sync.sh" > "$T/out" 2>&1; rc=$?
[ $rc = 1 ] && ok "exit 1" || bad "exit was $rc"
has "$LOG" "no https:// IP lookup services" "reason logged"
[ -s "$T/curl-calls" ] && bad "IP looked up anyway" || ok "no IP lookup"
[ -s "$T/calls" ] && bad "cloud called" || ok "no cloud calls"

echo; echo "passed $PASS, failed $FAILN"
[ "$FAILN" = 0 ]
