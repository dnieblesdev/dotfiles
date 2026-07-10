#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
TMP_REPO="$TMP_ROOT/repo"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# Build a disposable copy of the repository so tests never mutate the source tree.
mkdir -p "$TMP_REPO"
cp -a "$REPO_ROOT"/. "$TMP_REPO"
rm -rf "$TMP_REPO/.git"

export DOTLINK_HOME="$TMP_ROOT/home"
mkdir -p "$DOTLINK_HOME"
export DOTLINK_REPO_ROOT="$TMP_REPO"

BAD_PROFILE="$TMP_REPO/profiles/bad-test.sh"
ROLLBACK_A="$TMP_REPO/config/.config/dotlink-test-a"
ROLLBACK_B="$TMP_REPO/config/.config/dotlink-test-b"

assert_link() {
    local target="$1"
    local expected="$2"
    [ -L "$target" ] || { printf 'expected symlink: %s\n' "$target" >&2; exit 1; }
    [ "$(readlink "$target")" = "$expected" ] || { printf 'unexpected target for %s\n' "$target" >&2; exit 1; }
}

assert_missing() {
    local target="$1"
    [ ! -e "$target" ] && [ ! -L "$target" ] || { printf 'expected missing: %s\n' "$target" >&2; exit 1; }
}

"$TMP_REPO/bin/dotlink" list --profile base > "$TMP_ROOT/list.out"
grep -qx 'bash' "$TMP_ROOT/list.out"
"$TMP_REPO/bin/dotlink" list --profile=base > "$TMP_ROOT/list-equals.out"
grep -qx 'bash' "$TMP_ROOT/list-equals.out"
"$TMP_REPO/bin/dotlink" link --profile base
assert_link "$DOTLINK_HOME/.bashrc" "$TMP_REPO/bash/.bashrc"
assert_link "$DOTLINK_HOME/.gitconfig" "$TMP_REPO/git/.gitconfig"
"$TMP_REPO/bin/dotlink" verify --profile base
"$TMP_REPO/bin/dotlink" status --profile base > "$TMP_ROOT/status.out"
grep -q '^linked' "$TMP_ROOT/status.out"
"$TMP_REPO/bin/dotlink" unlink --profile base
assert_missing "$DOTLINK_HOME/.bashrc"

# Structured report: ordered results, JSON-only stdout, and shell-sensitive names.
printf 'quoted fixture\n' > "$TMP_REPO/bash/.quoted\"name"
"$TMP_REPO/bin/dotlink" link --report=json --profile base >"$TMP_ROOT/report-success.json" 2>"$TMP_ROOT/report-success.err"
python3 - "$TMP_ROOT/report-success.json" "$TMP_REPO" "$DOTLINK_HOME" <<'PY'
import json
import sys
report = json.load(open(sys.argv[1]))
repo, home = sys.argv[2:]
assert report["schema_version"] == 1
assert report["modules"] == ["bash", "git"]
assert report["status"] == "success"
assert report["failure"] is None
assert report["rollback"] == {"attempted": False, "completed": False, "removed_targets": [], "removed_directories": []}
assert [entry["outcome"] for entry in report["entries"]] == ["changed"] * len(report["entries"])
assert [(entry["module"], entry["source"], entry["target"]) for entry in report["entries"]] == [
    ("bash", f"{repo}/bash/.bashrc", f"{home}/.bashrc"),
    ("bash", f'{repo}/bash/.quoted"name', f'{home}/.quoted"name'),
    ("git", f"{repo}/git/.gitconfig", f"{home}/.gitconfig"),
]
PY
grep -q '^dotlink: linked ' "$TMP_ROOT/report-success.err"
"$TMP_REPO/bin/dotlink" link --report=json --profile base >"$TMP_ROOT/report-noop.json" 2>"$TMP_ROOT/report-noop.err"
python3 - "$TMP_ROOT/report-noop.json" <<'PY'
import json
import sys
report = json.load(open(sys.argv[1]))
assert report["status"] == "success"
assert all(entry["outcome"] == "unchanged" for entry in report["entries"])
assert report["rollback"]["attempted"] is False
PY
"$TMP_REPO/bin/dotlink" unlink --profile base
rm "$TMP_REPO/bash/.quoted\"name"

# JSON must escape ASCII control bytes in filenames.
control_filename=$'.control\001name'
printf 'control fixture\n' > "$TMP_REPO/bash/$control_filename"
"$TMP_REPO/bin/dotlink" link --report=json bash >"$TMP_ROOT/report-controls.json" 2>"$TMP_ROOT/report-controls.err"
python3 - "$TMP_ROOT/report-controls.json" "$TMP_REPO" "$DOTLINK_HOME" "$control_filename" <<'PY'
import json
import sys
report = json.load(open(sys.argv[1]))
repo, home, filename = sys.argv[2:]
expected_source = f"{repo}/bash/{filename}"
expected_target = f"{home}/{filename}"
entry = next(entry for entry in report["entries"] if entry["source"] == expected_source)
assert entry["target"] == expected_target
assert "\x01" in entry["source"]
PY
"$TMP_REPO/bin/dotlink" unlink bash
rm "$TMP_REPO/bash/$control_filename"

# Nested config entry link/unlink coverage.
"$TMP_REPO/bin/dotlink" link config
assert_link "$DOTLINK_HOME/.config/starship.toml" "$TMP_REPO/config/.config/starship.toml"
"$TMP_REPO/bin/dotlink" unlink config
assert_missing "$DOTLINK_HOME/.config/starship.toml"

if "$TMP_REPO/bin/dotlink" link --report=unsupported bash >"$TMP_ROOT/dotlink-bad-report.out" 2>"$TMP_ROOT/dotlink-bad-report.err"; then
    printf 'expected unsupported report value failure\n' >&2
    exit 1
fi
grep -q 'unsupported report value' "$TMP_ROOT/dotlink-bad-report.err"
assert_missing "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" status --report=json >"$TMP_ROOT/dotlink-status-report.out" 2>"$TMP_ROOT/dotlink-status-report.err"; then
    printf 'expected non-link report option failure\n' >&2
    exit 1
fi
grep -q 'unknown option: --report=json' "$TMP_ROOT/dotlink-status-report.err"
if "$TMP_REPO/bin/dotlink" link --report=json bash not-a-module >"$TMP_ROOT/dotlink-unknown-report.json" 2>"$TMP_ROOT/dotlink-unknown-report.err"; then
    printf 'expected unknown reported module failure\n' >&2
    exit 1
fi
python3 - "$TMP_ROOT/dotlink-unknown-report.json" <<'PY'
import json
import sys
report = json.load(open(sys.argv[1]))
assert report["status"] == "failed"
assert report["failure"]["module"] == "not-a-module"
assert report["failure"]["source"] is None
assert report["failure"]["target"] is None
assert report["failure"]["cause"]["code"] == "unknown_module"
assert report["entries"] == []
PY
assert_missing "$DOTLINK_HOME/.bashrc"

if "$TMP_REPO/bin/dotlink" link bash not-a-module >"$TMP_ROOT/dotlink-unknown-link.out" 2>"$TMP_ROOT/dotlink-unknown-link.err"; then
    printf 'expected unknown explicit module link failure\n' >&2
    exit 1
fi
grep -q 'unknown module: not-a-module' "$TMP_ROOT/dotlink-unknown-link.err"
assert_missing "$DOTLINK_HOME/.bashrc"

if "$TMP_REPO/bin/dotlink" status not-a-module >"$TMP_ROOT/dotlink-unknown-status.out" 2>"$TMP_ROOT/dotlink-unknown-status.err"; then
    printf 'expected unknown explicit module status failure\n' >&2
    exit 1
fi
grep -q 'unknown module: not-a-module' "$TMP_ROOT/dotlink-unknown-status.err"

if "$TMP_REPO/bin/dotlink" verify not-a-module >"$TMP_ROOT/dotlink-unknown-verify.out" 2>"$TMP_ROOT/dotlink-unknown-verify.err"; then
    printf 'expected unknown explicit module verify failure\n' >&2
    exit 1
fi
grep -q 'unknown module: not-a-module' "$TMP_ROOT/dotlink-unknown-verify.err"

if "$TMP_REPO/bin/dotlink" link scripts >"$TMP_ROOT/dotlink-scripts-link.out" 2>"$TMP_ROOT/dotlink-scripts-link.err"; then
    printf 'expected operational scripts directory link rejection\n' >&2
    exit 1
fi
grep -q 'unknown module: scripts' "$TMP_ROOT/dotlink-scripts-link.err"

if "$TMP_REPO/bin/dotlink" status scripts >"$TMP_ROOT/dotlink-scripts-status.out" 2>"$TMP_ROOT/dotlink-scripts-status.err"; then
    printf 'expected operational scripts directory status rejection\n' >&2
    exit 1
fi
grep -q 'unknown module: scripts' "$TMP_ROOT/dotlink-scripts-status.err"

if "$TMP_REPO/bin/dotlink" verify scripts >"$TMP_ROOT/dotlink-scripts-verify.out" 2>"$TMP_ROOT/dotlink-scripts-verify.err"; then
    printf 'expected operational scripts directory verify rejection\n' >&2
    exit 1
fi
grep -q 'unknown module: scripts' "$TMP_ROOT/dotlink-scripts-verify.err"

printf 'local config\n' > "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" link bash >"$TMP_ROOT/dotlink-conflict.out" 2>"$TMP_ROOT/dotlink-conflict.err"; then
    printf 'expected regular-file conflict\n' >&2
    exit 1
fi
grep -q 'conflict' "$TMP_ROOT/dotlink-conflict.err"
rm "$DOTLINK_HOME/.bashrc"

ln -s /tmp/not-owned "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" link bash >"$TMP_ROOT/dotlink-foreign-link.out" 2>"$TMP_ROOT/dotlink-foreign-link.err"; then
    printf 'expected foreign-symlink link conflict\n' >&2
    exit 1
fi
grep -q 'conflict' "$TMP_ROOT/dotlink-foreign-link.err"
[ -L "$DOTLINK_HOME/.bashrc" ] || { printf 'foreign symlink was replaced during link\n' >&2; exit 1; }
[ "$(readlink "$DOTLINK_HOME/.bashrc")" = /tmp/not-owned ] || { printf 'foreign symlink target changed during link\n' >&2; exit 1; }
rm "$DOTLINK_HOME/.bashrc"

ln -s /tmp/not-owned "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" unlink bash >"$TMP_ROOT/dotlink-unlink.out" 2>"$TMP_ROOT/dotlink-unlink.err"; then
    printf 'expected foreign-symlink unlink conflict\n' >&2
    exit 1
fi
[ -L "$DOTLINK_HOME/.bashrc" ] || { printf 'foreign symlink was removed\n' >&2; exit 1; }
rm "$DOTLINK_HOME/.bashrc"

cat > "$BAD_PROFILE" <<'BAD'
DOTLINK_PROFILE_MODULES=(bash)
touch /tmp/dotlink-should-not-run
BAD
if "$TMP_REPO/bin/dotlink" list --profile bad-test >"$TMP_ROOT/dotlink-bad.out" 2>"$TMP_ROOT/dotlink-bad.err"; then
    printf 'expected manifest validation failure\n' >&2
    exit 1
fi
assert_missing /tmp/dotlink-should-not-run

ln -s /tmp/broken-dotlink-target "$DOTLINK_HOME/.bashrc"
if "$TMP_REPO/bin/dotlink" link bash >"$TMP_ROOT/dotlink-broken-link.out" 2>"$TMP_ROOT/dotlink-broken-link.err"; then
    printf 'expected broken-symlink link conflict\n' >&2
    exit 1
fi
grep -q 'conflict' "$TMP_ROOT/dotlink-broken-link.err"
[ -L "$DOTLINK_HOME/.bashrc" ] || { printf 'broken symlink was removed during link\n' >&2; exit 1; }
[ "$(readlink "$DOTLINK_HOME/.bashrc")" = /tmp/broken-dotlink-target ] || { printf 'broken symlink target changed during link\n' >&2; exit 1; }
rm "$DOTLINK_HOME/.bashrc"

"$TMP_REPO/bin/dotlink" link git
rm "$DOTLINK_HOME/.gitconfig"
ln -s /tmp/drifted-dotlink-target "$DOTLINK_HOME/.gitconfig"
if "$TMP_REPO/bin/dotlink" verify git >"$TMP_ROOT/dotlink-drift-verify.out" 2>"$TMP_ROOT/dotlink-drift-verify.err"; then
    printf 'expected drifted verify failure\n' >&2
    exit 1
fi
grep -q '^conflict[[:space:]]\+git[[:space:]]' "$TMP_ROOT/dotlink-drift-verify.out"
rm "$DOTLINK_HOME/.gitconfig"
"$TMP_REPO/bin/dotlink" link git
rm "$DOTLINK_HOME/.gitconfig"
if "$TMP_REPO/bin/dotlink" verify git >"$TMP_ROOT/dotlink-partial-verify.out" 2>"$TMP_ROOT/dotlink-partial-verify.err"; then
    printf 'expected partial verify failure\n' >&2
    exit 1
fi
grep -q '^missing[[:space:]]\+git[[:space:]]' "$TMP_ROOT/dotlink-partial-verify.out"

printf 'one\n' > "$ROLLBACK_A"
printf 'two\n' > "$ROLLBACK_B"
mkdir -p "$DOTLINK_HOME/.config"
printf 'local conflict\n' > "$DOTLINK_HOME/.config/dotlink-test-b"
if "$TMP_REPO/bin/dotlink" link --report=json config >"$TMP_ROOT/dotlink-rollback.json" 2>"$TMP_ROOT/dotlink-rollback.err"; then
    printf 'expected config rollback conflict\n' >&2
    exit 1
fi
python3 - "$TMP_ROOT/dotlink-rollback.json" "$DOTLINK_HOME" <<'PY'
import json
import sys
report = json.load(open(sys.argv[1]))
home = sys.argv[2]
assert report["status"] == "failed"
assert [entry["outcome"] for entry in report["entries"]] == ["rolled_back", "failed"]
assert report["entries"][1]["cause"]["code"] == "conflict"
assert report["failure"]["target"] == f"{home}/.config/dotlink-test-b"
assert report["rollback"]["attempted"] is True
assert report["rollback"]["completed"] is True
assert report["rollback"]["removed_targets"] == [f"{home}/.config/dotlink-test-a"]
PY
grep -q '^dotlink: linked ' "$TMP_ROOT/dotlink-rollback.err"
grep -q 'conflict: refusing' "$TMP_ROOT/dotlink-rollback.err"
assert_missing "$DOTLINK_HOME/.config/dotlink-test-a"
[ -f "$DOTLINK_HOME/.config/dotlink-test-b" ] || { printf 'rollback conflict file was removed\n' >&2; exit 1; }
grep -q 'local conflict' "$DOTLINK_HOME/.config/dotlink-test-b"

# Profile path traversal rejection.
for bad_profile in '../base' 'foo/bar' '.hidden'; do
    if "$TMP_REPO/bin/dotlink" list --profile "$bad_profile" >"$TMP_ROOT/dotlink-bad-profile-${bad_profile//\//-}.out" 2>"$TMP_ROOT/dotlink-bad-profile-${bad_profile//\//-}.err"; then
        printf 'expected invalid profile rejection for --profile %s\n' "$bad_profile" >&2
        exit 1
    fi
    grep -q 'invalid profile name' "$TMP_ROOT/dotlink-bad-profile-${bad_profile//\//-}.err"
done
if "$TMP_REPO/bin/dotlink" list --profile= >"$TMP_ROOT/dotlink-bad-profile-empty.out" 2>"$TMP_ROOT/dotlink-bad-profile-empty.err"; then
    printf 'expected invalid profile rejection for --profile=\n' >&2
    exit 1
fi
grep -q 'invalid profile name' "$TMP_ROOT/dotlink-bad-profile-empty.err"

# --profile and explicit modules are mutually exclusive.
if "$TMP_REPO/bin/dotlink" link --profile base bash >"$TMP_ROOT/dotlink-profile-explicit.out" 2>"$TMP_ROOT/dotlink-profile-explicit.err"; then
    printf 'expected --profile + explicit module rejection\n' >&2
    exit 1
fi
grep -q 'cannot combine --profile with explicit modules' "$TMP_ROOT/dotlink-profile-explicit.err"
if "$TMP_REPO/bin/dotlink" status --profile=base bash >"$TMP_ROOT/dotlink-profile-equals-explicit.out" 2>"$TMP_ROOT/dotlink-profile-equals-explicit.err"; then
    printf 'expected --profile= + explicit module rejection\n' >&2
    exit 1
fi
grep -q 'cannot combine --profile with explicit modules' "$TMP_ROOT/dotlink-profile-equals-explicit.err"

# Source deleted after linking is reported as drift by orphan detection.
"$TMP_REPO/bin/dotlink" link bash
rm "$TMP_REPO/bash/.bashrc"
"$TMP_REPO/bin/dotlink" status bash >"$TMP_ROOT/dotlink-deleted-status.out" 2>"$TMP_ROOT/dotlink-deleted-status.err"
grep -q '^drift[[:space:]]' "$TMP_ROOT/dotlink-deleted-status.out"
grep -q '.bashrc' "$TMP_ROOT/dotlink-deleted-status.out"
if "$TMP_REPO/bin/dotlink" verify bash >"$TMP_ROOT/dotlink-deleted-verify.out" 2>"$TMP_ROOT/dotlink-deleted-verify.err"; then
    printf 'expected verify failure after source deletion\n' >&2
    exit 1
fi
grep -q '^drift[[:space:]]' "$TMP_ROOT/dotlink-deleted-verify.out"
grep -q '.bashrc' "$TMP_ROOT/dotlink-deleted-verify.out"
rm "$DOTLINK_HOME/.bashrc"

# real_path fallback chain: readlink-only and pure-shell fallbacks.
STUB_DIR="$TMP_ROOT/stubs"
mkdir -p "$STUB_DIR"
READLINK_BIN="$(command -v readlink)"

cat > "$STUB_DIR/realpath" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_DIR/realpath"

cat > "$STUB_DIR/python3" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_DIR/python3"

cat > "$STUB_DIR/readlink" <<EOF
#!/bin/sh
exec "$READLINK_BIN" "\$@"
EOF
chmod +x "$STUB_DIR/readlink"

(
    PATH="$STUB_DIR"
    hash -r
    DOTLINK_REPO_ROOT="$TMP_REPO"
    # shellcheck source=/dev/null
    source "$TMP_REPO/dotlink/dotlink.sh"
    [ "$(real_path "$TMP_REPO/bash/.bashrc")" = "$TMP_REPO/bash/.bashrc" ]
    [ "$(real_path "$TMP_REPO/bash/./.bashrc")" = "$TMP_REPO/bash/.bashrc" ]
    [ "$(real_path "~/foo")" = "$HOME/foo" ]
)

# Mask readlink too to exercise the pure-shell fallback.
cat > "$STUB_DIR/readlink" <<'EOF'
#!/bin/sh
exit 1
EOF

(
    PATH="$STUB_DIR"
    hash -r
    DOTLINK_REPO_ROOT="$TMP_REPO"
    # shellcheck source=/dev/null
    source "$TMP_REPO/dotlink/dotlink.sh"
    [ "$(real_path "$TMP_REPO/bash/.bashrc")" = "$TMP_REPO/bash/.bashrc" ]
    [ "$(real_path "$TMP_REPO/bash/./.bashrc")" = "$TMP_REPO/bash/.bashrc" ]
    [ "$(real_path "~/foo")" = "$HOME/foo" ]
    [ "$(real_path "foo/bar/../baz")" = "foo/baz" ]
    [ "$(real_path "foo/bar/../baz/qux")" = "foo/baz/qux" ]
    [ "$(real_path ".")" = "." ]
)

# Relative repo-owned symlink is recognized as linked.
printf '# restored\n' > "$TMP_REPO/bash/.bashrc"
ln -s "../repo/bash/.bashrc" "$DOTLINK_HOME/.bashrc"
"$TMP_REPO/bin/dotlink" status bash >"$TMP_ROOT/dotlink-relative-status.out" 2>"$TMP_ROOT/dotlink-relative-status.err"
grep -q '^linked[[:space:]]' "$TMP_ROOT/dotlink-relative-status.out"
grep -q '.bashrc' "$TMP_ROOT/dotlink-relative-status.out"
rm "$DOTLINK_HOME/.bashrc"

# Makefile check handles paths containing spaces.
cat > "$TMP_REPO/scripts/test file.sh" <<'EOF'
#!/usr/bin/env bash
echo ok
EOF
chmod +x "$TMP_REPO/scripts/test file.sh"
(cd "$TMP_REPO" && make check) >"$TMP_ROOT/make-check-spaces.out" 2>"$TMP_ROOT/make-check-spaces.err"

# status without args scans ALL known modules, not just base profile.
"$TMP_REPO/bin/dotlink" link bash git zsh config > /dev/null 2>&1 || true
"$TMP_REPO/bin/dotlink" status > "$TMP_ROOT/status-all.out" 2>/dev/null || true
grep -q 'bash' "$TMP_ROOT/status-all.out" || { printf 'FAIL: status missing bash\n' >&2; exit 1; }
grep -q 'git' "$TMP_ROOT/status-all.out" || { printf 'FAIL: status missing git\n' >&2; exit 1; }
grep -q 'zsh' "$TMP_ROOT/status-all.out" || { printf 'FAIL: status missing zsh\n' >&2; exit 1; }
grep -q 'config' "$TMP_ROOT/status-all.out" || { printf 'FAIL: status missing config\n' >&2; exit 1; }
"$TMP_REPO/bin/dotlink" unlink bash git zsh config > /dev/null 2>&1 || true

printf 'dotlink tests passed\n'
