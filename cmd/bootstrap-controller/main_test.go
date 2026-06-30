package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/dnieblesdev/dotfiles/internal/controller"
)

func TestHandshakeSuccessAndApply(t *testing.T) {
	shellPath := writeFakeShell(t, "ok")
	stdout, stderr, code := runController(t, []string{"--shell", shellPath}, "")
	if code != 0 {
		t.Fatalf("expected success, got code %d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, "Go controller handshake ok") {
		t.Fatalf("expected handshake banner, got %s", stdout)
	}
	if !strings.Contains(stdout, "apply:apply --only system-packages,brew-tools") {
		t.Fatalf("expected shell apply invocation, got %s", stdout)
	}
}

func TestHandshakeFailureFallsBackToShell(t *testing.T) {
	shellPath := writeFakeShell(t, "unsupported")
	stdout, stderr, code := runController(t, []string{"--shell", shellPath}, "")
	if code != 0 {
		t.Fatalf("expected fallback success, got code %d stderr=%s", code, stderr)
	}
	if !strings.Contains(stderr, "Go controller unavailable") {
		t.Fatalf("expected fallback warning, got %s", stderr)
	}
	if !strings.Contains(stdout, "apply:") {
		t.Fatalf("expected shell fallback output, got %s", stdout)
	}
}

func TestOutdatedGoFallsBackToShell(t *testing.T) {
	shellPath := writeFakeShell(t, "ok")
	stdout, stderr, code := runController(t, []string{"--shell", shellPath, "--protocol-version", "0"}, "")
	if code != 0 {
		t.Fatalf("expected fallback success, got code %d stderr=%s", code, stderr)
	}
	if !strings.Contains(stderr, "Go controller unavailable") {
		t.Fatalf("expected outdated-go fallback warning, got %s", stderr)
	}
	if !strings.Contains(stdout, "apply:") {
		t.Fatalf("expected shell fallback output, got %s", stdout)
	}
}

func TestControllerDoesNotRequireStateOrCatalogFiles(t *testing.T) {
	root := t.TempDir()
	bootstrapDir := filepath.Join(root, "bootstrap")
	if err := os.MkdirAll(bootstrapDir, 0o755); err != nil {
		t.Fatal(err)
	}
	shellPath := writeFakeShellAt(t, filepath.Join(bootstrapDir, "install.sh"), "ok")
	stdout, stderr, code := runController(t, []string{"--shell", shellPath}, "")
	if code != 0 {
		t.Fatalf("expected success without lib files, got code %d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, "Go controller handshake ok") {
		t.Fatalf("expected handshake banner, got %s", stdout)
	}
	if _, err := os.Stat(filepath.Join(root, "bootstrap", "lib", "state.sh")); !os.IsNotExist(err) {
		t.Fatalf("expected no direct dependency on state.sh, stat err=%v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "bootstrap", "lib", "catalog.sh")); !os.IsNotExist(err) {
		t.Fatalf("expected no direct dependency on catalog.sh, stat err=%v", err)
	}
}

func TestValidateShellPathAcceptsShellInTrustedRoot(t *testing.T) {
	trustedRoot := t.TempDir()
	bootstrapDir := filepath.Join(trustedRoot, "bootstrap")
	if err := os.MkdirAll(bootstrapDir, 0o755); err != nil {
		t.Fatal(err)
	}
	shellPath := writeFakeShellAt(t, filepath.Join(bootstrapDir, "install.sh"), "ok")

	resolved, err := validateShellPath(trustedRoot, shellPath)
	if err != nil {
		t.Fatalf("expected shell in trusted root to validate, got %v", err)
	}
	if resolved == "" {
		t.Fatalf("expected non-empty resolved path")
	}
}

func TestValidateShellPathRejectsShellOutsideTrustedRoot(t *testing.T) {
	trustedRoot := t.TempDir()
	otherRoot := t.TempDir()
	otherBootstrap := filepath.Join(otherRoot, "bootstrap")
	if err := os.MkdirAll(otherBootstrap, 0o755); err != nil {
		t.Fatal(err)
	}
	shellPath := writeFakeShellAt(t, filepath.Join(otherBootstrap, "install.sh"), "ok")

	if _, err := validateShellPath(trustedRoot, shellPath); err == nil {
		t.Fatalf("expected shell outside trusted root to be rejected")
	}
}

func TestValidateShellPathRejectsNonExecutable(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix permission bits are not enforced on windows")
	}
	trustedRoot := t.TempDir()
	bootstrapDir := filepath.Join(trustedRoot, "bootstrap")
	if err := os.MkdirAll(bootstrapDir, 0o755); err != nil {
		t.Fatal(err)
	}
	shellPath := filepath.Join(bootstrapDir, "install.sh")
	if err := os.WriteFile(shellPath, []byte("#!/usr/bin/env bash\nexit 0\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := validateShellPath(trustedRoot, shellPath); err == nil {
		t.Fatalf("expected non-executable shell to be rejected")
	}
}

func TestValidateShellPathRejectsWorldWritable(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("unix permission bits are not enforced on windows")
	}
	if os.Geteuid() == 0 {
		t.Skip("root bypasses file mode checks")
	}
	trustedRoot := t.TempDir()
	bootstrapDir := filepath.Join(trustedRoot, "bootstrap")
	if err := os.MkdirAll(bootstrapDir, 0o755); err != nil {
		t.Fatal(err)
	}
	shellPath := filepath.Join(bootstrapDir, "install.sh")
	if err := os.WriteFile(shellPath, []byte("#!/usr/bin/env bash\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	// Force the group/other write bits on so the validation has a chance to
	// reject the file regardless of the inherited umask.
	if err := os.Chmod(shellPath, 0o777); err != nil {
		t.Fatal(err)
	}

	if _, err := validateShellPath(trustedRoot, shellPath); err == nil {
		t.Fatalf("expected world-writable shell to be rejected")
	}
}

func TestValidateShellPathRejectsMissingFile(t *testing.T) {
	trustedRoot := t.TempDir()
	bootstrapDir := filepath.Join(trustedRoot, "bootstrap")
	if err := os.MkdirAll(bootstrapDir, 0o755); err != nil {
		t.Fatal(err)
	}
	shellPath := filepath.Join(bootstrapDir, "install.sh")

	if _, err := validateShellPath(trustedRoot, shellPath); err == nil {
		t.Fatalf("expected missing shell to be rejected")
	}
}

func TestValidateShellPathRejectsSymlinkEscape(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlink behaviour differs on windows")
	}
	trustedRoot := t.TempDir()
	bootstrapDir := filepath.Join(trustedRoot, "bootstrap")
	if err := os.MkdirAll(bootstrapDir, 0o755); err != nil {
		t.Fatal(err)
	}
	otherRoot := t.TempDir()
	otherBootstrap := filepath.Join(otherRoot, "bootstrap")
	if err := os.MkdirAll(otherBootstrap, 0o755); err != nil {
		t.Fatal(err)
	}
	realShell := writeFakeShellAt(t, filepath.Join(otherBootstrap, "install.sh"), "ok")
	linkPath := filepath.Join(bootstrapDir, "install.sh")
	if err := os.Symlink(realShell, linkPath); err != nil {
		t.Skipf("symlink unsupported in test environment: %v", err)
	}

	if _, err := validateShellPath(trustedRoot, linkPath); err == nil {
		t.Fatalf("expected symlink escaping the trusted root to be rejected")
	}
}

func TestRunRejectsShellOutsideTrustedRoot(t *testing.T) {
	trustedRoot := t.TempDir()
	otherRoot := t.TempDir()
	otherBootstrap := filepath.Join(otherRoot, "bootstrap")
	if err := os.MkdirAll(otherBootstrap, 0o755); err != nil {
		t.Fatal(err)
	}
	shellPath := writeFakeShellAt(t, filepath.Join(otherBootstrap, "install.sh"), "ok")

	origResolver := dotfilesRootResolver
	dotfilesRootResolver = func() (string, error) { return trustedRoot, nil }
	t.Cleanup(func() { dotfilesRootResolver = origResolver })

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	code := run(context.Background(), []string{"--shell", shellPath}, strings.NewReader(""), &stdout, &stderr)
	if code != 2 {
		t.Fatalf("expected rejection code 2, got %d stderr=%s", code, stderr.String())
	}
	if !strings.Contains(stderr.String(), "outside the trusted dotfiles root") {
		t.Fatalf("expected trusted-root rejection reason, got %s", stderr.String())
	}
}

func TestRunAcceptsShellFromEnvVar(t *testing.T) {
	trustedRoot := t.TempDir()
	bootstrapDir := filepath.Join(trustedRoot, "bootstrap")
	if err := os.MkdirAll(bootstrapDir, 0o755); err != nil {
		t.Fatal(err)
	}
	shellPath := writeFakeShellAt(t, filepath.Join(bootstrapDir, "install.sh"), "ok")

	origResolver := dotfilesRootResolver
	dotfilesRootResolver = func() (string, error) { return trustedRoot, nil }
	t.Cleanup(func() { dotfilesRootResolver = origResolver })

	origShellEnv, hadShellEnv := os.LookupEnv("BOOTSTRAP_SHELL_PATH")
	t.Cleanup(func() {
		if hadShellEnv {
			_ = os.Setenv("BOOTSTRAP_SHELL_PATH", origShellEnv)
		} else {
			_ = os.Unsetenv("BOOTSTRAP_SHELL_PATH")
		}
	})
	if err := os.Setenv("BOOTSTRAP_SHELL_PATH", shellPath); err != nil {
		t.Fatal(err)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	code := run(context.Background(), nil, strings.NewReader(""), &stdout, &stderr)
	if code != 0 {
		t.Fatalf("expected success via env var, got %d stderr=%s", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "Go controller handshake ok") {
		t.Fatalf("expected handshake banner, got %s", stdout.String())
	}
}

func TestSanitizeShellEnvDropsSecretsButKeepsBootstrap(t *testing.T) {
	t.Setenv("SECRET_TOKEN", "hunter2")
	t.Setenv("BOOTSTRAP_TEST_VAR", "ok")
	t.Setenv("HOME", "/tmp/fake-home")
	t.Setenv("USER", "alice")
	t.Setenv("PATH", "/usr/bin")

	env := controller.SanitizeShellEnv()
	seen := map[string]string{}
	for _, kv := range env {
		name, value, _ := strings.Cut(kv, "=")
		seen[name] = value
	}

	if seen["SECRET_TOKEN"] != "" {
		t.Fatalf("expected SECRET_TOKEN to be dropped, got env=%v", env)
	}
	if seen["BOOTSTRAP_TEST_VAR"] != "ok" {
		t.Fatalf("expected BOOTSTRAP_TEST_VAR to be preserved, got env=%v", env)
	}
	if seen["HOME"] != "/tmp/fake-home" {
		t.Fatalf("expected HOME to be preserved, got env=%v", env)
	}
	if seen["USER"] != "alice" {
		t.Fatalf("expected USER to be preserved, got env=%v", env)
	}
	if seen["PATH"] != "/usr/bin" {
		t.Fatalf("expected PATH to be preserved, got env=%v", env)
	}
	for _, kv := range env {
		name, _, _ := strings.Cut(kv, "=")
		if name == "SECRET_TOKEN" {
			t.Fatalf("expected no leaked secrets in env: %v", env)
		}
	}
}

func runController(t *testing.T, args []string, input string) (string, string, int) {
	t.Helper()

	// The fake shell lives at <root>/bootstrap/install.sh. Override the dotfiles
	// root resolver so path validation accepts the test fixture. We extract the
	// shell path from --shell when present; otherwise we fall back to a temp dir
	// so tests that resolve the default path still find a valid trusted root.
	trustedRoot := t.TempDir()
	for i, arg := range args {
		if arg == "--shell" && i+1 < len(args) {
			shellDir := filepath.Dir(args[i+1])
			if filepath.Base(shellDir) == "bootstrap" {
				trustedRoot = filepath.Dir(shellDir)
			}
			break
		}
	}
	origResolver := dotfilesRootResolver
	dotfilesRootResolver = func() (string, error) { return trustedRoot, nil }
	t.Cleanup(func() { dotfilesRootResolver = origResolver })

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	code := run(context.Background(), args, strings.NewReader(input), &stdout, &stderr)
	return stdout.String(), stderr.String(), code
}

func writeFakeShell(t *testing.T, mode string) string {
	t.Helper()
	root := t.TempDir()
	return writeFakeShellAt(t, filepath.Join(root, "bootstrap", "install.sh"), mode)
}

func writeFakeShellAt(t *testing.T, shellPath string, mode string) string {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(shellPath), 0o755); err != nil {
		t.Fatal(err)
	}

	script := strings.ReplaceAll(`#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  controller)
    request="$(cat)"
    if [[ "$request" == *'"protocol_version":0'* ]]; then
      cat <<'JSON'
{
  "protocol_version": 1,
  "status": "unsupported",
  "expected_protocol_version": 1,
  "received_protocol_version": 0,
  "error": "controller protocol mismatch"
}
JSON
      exit 64
    fi
    if [ "__MODE__" = "unsupported" ]; then
      cat <<'JSON'
{
  "protocol_version": 1,
  "status": "unsupported",
  "expected_protocol_version": 1,
  "received_protocol_version": 1,
  "error": "controller protocol mismatch"
}
JSON
      exit 64
    fi
    cat <<'JSON'
{
  "protocol_version": 1,
  "status": "ok",
  "shell_contract": "bootstrap-controller",
  "shell_contract_version": 1,
  "bootstrap_schema_version": 1,
  "bootstrap_catalog_version": 1,
  "supported_shell_commands": ["list", "plan", "apply"]
}
JSON
    ;;
  list)
    cat <<'JSON'
{
  "schema_version": 1,
  "catalog_version": 1,
  "catalog_hash": "abc123",
  "context": {
    "target_user": "alice",
    "target_home": "/home/alice",
    "effective_user": "alice",
    "execution_context": "user-shell",
    "frontend": "list"
  },
  "actions": [
    {"id": "system-packages", "label": "System packages", "group": "system", "privilege": "elevated", "deps": [], "status": "pending"},
    {"id": "brew-tools", "label": "Brew tools", "group": "brew", "privilege": "user", "deps": ["system-packages"], "status": "pending"}
  ]
}
JSON
    ;;
  apply)
    printf 'apply:%s\n' "$*"
    ;;
  *)
    exit 2
    ;;
esac
`, "__MODE__", mode)
	if err := os.WriteFile(shellPath, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS != "windows" {
		_ = os.Chmod(shellPath, 0o755)
	}
	return shellPath
}
