#!/usr/bin/env bash
# Tests pclaude's macOS credential sync against a fake Keychain, so the real one is never
# touched. Uses the real plutil (what pclaude parses with), hence macOS only.
set -uo pipefail
[ "$(uname -s)" = Darwin ] || { echo "skipped: the credential sync only runs on macOS"; exit 0; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stand-in for `security`: one item, stored in $FAKE_KEYCHAIN. It only answers the exact
# calls pclaude should make, so targeting the wrong item or account fails the tests.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/security" <<'EOF'
#!/usr/bin/env bash
[ -z "${FAKE_LOCKED:-}" ] || exit 51
case "$1" in
  find-generic-password)
    [ "$*" = "find-generic-password -s Claude Code-credentials -a tester -w" ] || exit 44
    [ -f "$FAKE_KEYCHAIN" ] || exit 44
    cat "$FAKE_KEYCHAIN"; echo ;;
  -i)
    read -r cmd; echo "$cmd" >>"$FAKE_KEYCHAIN.log"
    prefix="add-generic-password -U -s \"Claude Code-credentials\" -a \"tester\" -X "
    case "$cmd" in "$prefix"*) ;; *) exit 0 ;; esac   # the real one may also exit 0 here
    hex="${cmd#"$prefix"}"; printf "$(printf %s "$hex" | sed 's/../\\x&/g')" >"$FAKE_KEYCHAIN" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$tmp/bin/security"
export PATH="$tmp/bin:$PATH" FAKE_KEYCHAIN="$tmp/keychain" HOME="$tmp/home" USER=tester

# shellcheck source=pclaude
source "$root/pclaude"
set +e

# A login whose access token and expiry are the given ones.
creds() { printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"r","expiresAt":%s}}' "$1" "$2"; }
keychain() { printf '%s' "$1" >"$FAKE_KEYCHAIN"; }
file() { printf '%s' "$1" >"$CREDS"; }
run_sync() { status=0; sync_credentials 2>"$tmp/stderr" || status=$?; }
eq() { [ "$1" = "$2" ] || { printf '  expected: %s\n  got:      %s\n' "$2" "$1"; exit 1; }; }
mode() { stat -f %Lp "$1"; }
no_keychain_writes() { [ ! -e "$FAKE_KEYCHAIN.log" ] || { echo "  unexpected Keychain write"; exit 1; }; }

test_keychain_newer_overwrites_file() {
  keychain "$(creds new 200)"; file "$(creds old 100)"; run_sync
  eq "$status" 0; eq "$(cat "$CREDS")" "$(creds new 200)"; eq "$(mode "$CREDS")" 600; no_keychain_writes
}
test_file_newer_goes_back_to_keychain() {
  keychain "$(creds old 100)"; file "$(creds new 200)"; run_sync
  eq "$status" 0; eq "$(cat "$FAKE_KEYCHAIN")" "$(creds new 200)"; eq "$(cat "$CREDS")" "$(creds new 200)"
  eq "$(cat "$tmp/stderr")" ""
}
test_equal_touches_nothing() {
  keychain "$(creds same 100)"; file "$(creds same 100)"; chmod 644 "$CREDS"; run_sync
  eq "$status" 0; eq "$(mode "$CREDS")" 644; no_keychain_writes
}
test_file_is_created_private_despite_umask() {
  umask 022; keychain "$(creds new 200)"; run_sync
  eq "$status" 0; eq "$(mode "$CREDS")" 600; eq "$(ls -A "$HOME/.claude")" .credentials.json
}
test_world_readable_file_is_replaced_private() {
  keychain "$(creds new 200)"; file "$(creds old 100)"; chmod 644 "$CREDS"; run_sync
  eq "$(mode "$CREDS")" 600
}
test_only_file_restores_keychain() {
  file "$(creds only 100)"; run_sync
  eq "$status" 0; eq "$(cat "$FAKE_KEYCHAIN")" "$(creds only 100)"
}
test_neither_is_not_logged_in() {
  run_sync
  eq "$status" 1; no_keychain_writes; [ ! -e "$CREDS" ] || { echo "  file created"; exit 1; }
}
test_garbage_file_loses() {
  keychain "$(creds good 1)"; file "not json"; run_sync
  eq "$status" 0; eq "$(cat "$CREDS")" "$(creds good 1)"
}
test_garbage_keychain_loses() {
  keychain "not json"; file "$(creds good 1)"; run_sync
  eq "$status" 0; eq "$(cat "$FAKE_KEYCHAIN")" "$(creds good 1)"
}
test_file_without_refresh_token_never_reaches_keychain() {
  file '{"claudeAiOauth":{"accessToken":"a","expiresAt":9999999999999}}'; run_sync
  eq "$status" 1; no_keychain_writes
}
test_non_numeric_expiry_is_not_a_login() {
  file '{"claudeAiOauth":{"accessToken":"a","refreshToken":"r","expiresAt":"soon"}}'; run_sync
  eq "$status" 1; no_keychain_writes
}
test_awkward_token_survives_round_trip() {
  local nasty='a b \"q\" '\''s $(x) `y` %s %% \\ é 🔑'
  file "$(creds "$nasty" 200)"; run_sync
  eq "$(cat "$FAKE_KEYCHAIN")" "$(creds "$nasty" 200)"
  rm "$CREDS"; run_sync
  eq "$(cat "$CREDS")" "$(creds "$nasty" 200)"
}
test_failed_keychain_write_warns_and_keeps_file() {
  file "$(creds new 200)"; FAKE_LOCKED=1 run_sync
  eq "$status" 0; eq "$(cat "$CREDS")" "$(creds new 200)"
  grep -q "could not update the Keychain" "$tmp/stderr" || { echo "  no warning"; exit 1; }
}

failed=0
for t in $(declare -F | awk '/ test_/ {print $3}'); do
  rm -rf "$HOME" "$FAKE_KEYCHAIN" "$FAKE_KEYCHAIN.log"; mkdir -p "$HOME/.claude"
  ( set -e; "$t" )
  if [ $? = 0 ]; then echo "ok   ${t#test_}"; else echo "FAIL ${t#test_}"; failed=1; fi
done
exit "$failed"
