#!/bin/sh
# Tests for bin/mlisb with a fake `open`; only temp files are touched.
here=$(cd "$(dirname "$0")" && pwd)
mlisb=$here/mlisb
T=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/mlisb-test-XXXXXX")" && pwd)
trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
cat > "$T/bin/open" <<'EOF'
#!/bin/sh
{ echo "open"; for a in "$@"; do echo "  $a"; done; } >> "$OPEN_LOG"
EOF
chmod +x "$T/bin/open"
PATH=$T/bin:$PATH
OPEN_LOG=$T/log
export PATH OPEN_LOG
unset MLISB_BUNDLE_ID
B=net.favoretti.mlisb

fails=0
check() { # name expected-log
  want=$(printf '%s' "$2")
  got=$(cat "$OPEN_LOG" 2>/dev/null)
  if [ "$got" = "$want" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "--- want"; echo "$want"; echo "--- got"; echo "$got"; fails=$((fails + 1)); fi
}
assert() { # name command...
  name=$1; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
fresh() { : > "$OPEN_LOG"; }
count() { grep -c -- "$1" "$2" || true; }

cd "$T" || exit 1
mkdir -p dir
printf 'a\nb\nc\n' > notes.md
printf 'x\n' > 'odd:7.md'

fresh; sh "$mlisb" notes.md dir
check "plain open" "open
  -b
  $B
  notes.md
  dir"

fresh; sh "$mlisb" notes.md:2
check "file:line" "open
  -b
  $B
  $T/notes.md
open
  -b
  $B
  mlisb://line?file=$(printf %s "$T/notes.md" | od -An -v -tx1 | tr -d ' \n' | sed 's/../%&/g')&line=2"

fresh; sh "$mlisb" --line 3 notes.md
assert "--line sends a line request" grep -q "&line=3\$" "$OPEN_LOG"
assert "--line opens the file first" sh -c "sed -n 4p '$OPEN_LOG' | grep -q 'notes.md'"

fresh; sh "$mlisb" 'odd:7.md'
check "existing file with a colon opens as is" "open
  -b
  $B
  odd:7.md"

fresh; sh "$mlisb" fresh.md:5
assert "missing markdown file is created" test -f fresh.md
assert "missing file with :N still gets the line" grep -q "&line=5\$" "$OPEN_LOG"

for ext in mkd mdx qmd rmd mdc; do
  fresh; sh "$mlisb" "extra.$ext"
  assert "creates missing .$ext file" test -f "extra.$ext"
  fresh; : > "$T/n.$ext"; printf '{"tool_input":{"file_path":"%s/n.%s"}}' "$T" "$ext" | sh "$mlisb" notify
  assert "notify accepts .$ext" grep -q "n.$ext" "$OPEN_LOG"
done

fresh; sh "$mlisb" made.md
assert "creates missing markdown file" test -f made.md
check "created file is opened" "open
  -b
  $B
  made.md"

fresh; printf 'hello\n' | sh "$mlisb" - >/dev/null
tmp=$(sed -n 4p "$OPEN_LOG" | sed 's/^  //')
assert "stdin opens a temp .md" test "${tmp%.md}" != "$tmp"
assert "stdin content is in the file" grep -q hello "$tmp"
rm -f "$tmp"

fresh; MLISB_BUNDLE_ID=x.y sh "$mlisb" notes.md
assert "MLISB_BUNDLE_ID is honoured" grep -qx '  x.y' "$OPEN_LOG"

# --- notify
md=$T/note.md; : > "$md"
for key in '"tool_input":{"file_path":"%s"}' '"tool_input":{"path":"%s"}' '"tool_response":{"filePath":"%s"}'; do
  fresh
  # shellcheck disable=SC2059
  json="{$(printf "$key" "$md")}"
  out=$(printf '%s' "$json" | sh "$mlisb" notify 2>&1); st=$?
  check "notify $(echo "$key" | cut -d'"' -f2,4)" "open
  -g
  -b
  $B
  $md"
  assert "notify is silent and exits 0" test -z "$out" -a $st -eq 0
done

fresh; out=$(echo 'not json {' | sh "$mlisb" notify 2>&1); st=$?
check "notify with garbage opens nothing" ""
assert "notify with garbage is silent, exit 0" test -z "$out" -a $st -eq 0

: > "$T/a.txt"
fresh; out=$(printf '{"tool_input":{"file_path":"%s/a.txt"}}' "$T" | sh "$mlisb" notify 2>&1); st=$?
check "notify ignores non-markdown" ""
assert "notify non-markdown exit 0" test -z "$out" -a $st -eq 0

fresh; printf '{"tool_input":{"file_path":"%s/missing.md"}}' "$T" | sh "$mlisb" notify
check "notify ignores a missing file" ""

fresh; printf '{"tool_input":{"command":"ls"}}' | sh "$mlisb" notify; st=$?
check "notify with no path opens nothing" ""
assert "notify with no path exit 0" test $st -eq 0

fresh; : > "$T/up.MD"; printf '{"tool_input":{"file_path":"%s/up.MD"}}' "$T" | sh "$mlisb" notify
assert "notify accepts an upper-case extension" grep -q 'up.MD' "$OPEN_LOG"


# --- hook
S=$T/s/settings.json
cmd="$mlisb notify"
hook() { sh "$mlisb" hook "$@" --settings "$S"; }

out=$(hook install); st=$?
assert "install creates a missing file" test -f "$S" -a $st -eq 0
assert "install output names the path" sh -c "echo '$out' | grep -qF '$S'"
assert "created file is valid JSON" plutil -convert json -o /dev/null "$S"
assert "created file has the matcher" grep -q 'Write|Edit|MultiEdit' "$S"
assert "created file has the command" grep -qF "\"$cmd\"" "$S"
assert "no backup for a new file" test ! -e "$S.mlisb-backup"

hook install >/dev/null
assert "install twice does not duplicate" test "$(count "$cmd" "$S")" = 1
assert "install twice leaves a backup" test -f "$S.mlisb-backup"

cat > "$S" <<'EOF'
{"theme":"dark","permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo done"}]}],"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/x/other"}]}]}}
EOF
cp "$S" "$T/orig"
hook install >/dev/null
assert "install keeps other settings" sh -c "grep -q '\"theme\": \"dark\"' '$S' && grep -q 'Bash(ls)' '$S' && grep -q 'echo done' '$S' && grep -q '/x/other' '$S'"
assert "backup equals the previous file" cmp -s "$T/orig" "$S.mlisb-backup"
assert "installed alongside" grep -qF "\"$cmd\"" "$S"
hook uninstall >/dev/null
assert "uninstall removes only ours" sh -c "! grep -qF '$cmd' '$S' && grep -q '/x/other' '$S' && grep -q 'echo done' '$S' && grep -q 'dark' '$S'"
assert "uninstall result is valid JSON" plutil -convert json -o /dev/null "$S"
out=$(hook uninstall); st=$?
assert "uninstall when absent is a no-op, exit 0" test $st -eq 0

printf '{"hooks":{"PostToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"/x/other"},{"type":"command","command":"%s"}]}]}}' "$cmd" > "$S"
hook uninstall >/dev/null
assert "uninstall keeps a sibling hook in the same entry" sh -c "grep -q '/x/other' '$S' && ! grep -qF '$cmd' '$S'"

printf '{ broken' > "$S"; cp "$S" "$T/orig"
out=$(hook install 2>&1); st=$?
assert "invalid JSON is refused" test $st -ne 0
assert "refusal message is clear" sh -c "echo '$out' | grep -q 'not valid JSON'"
assert "invalid file untouched" cmp -s "$T/orig" "$S"
rm -f "$S.mlisb-backup"
hook uninstall >/dev/null 2>&1; st=$?
assert "uninstall of invalid JSON refused, untouched" sh -c "test $st -ne 0 && cmp -s '$T/orig' '$S'"

S2=$T/never/settings.json
out=$(sh "$mlisb" hook uninstall --settings "$S2"); st=$?
assert "uninstall with no file is a no-op" test $st -eq 0 -a ! -e "$S2"

fresh; sh "$mlisb" --bogus 2>"$T/err"; st=$?
assert "unknown option exits 2" test $st -eq 2
assert "unknown option prints help to stderr" grep -q usage "$T/err"
assert "unknown option opens nothing" test ! -s "$OPEN_LOG"
assert "--help succeeds" sh -c "sh '$mlisb' --help | grep -q 'hook install'"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
