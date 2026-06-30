package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/dnieblesdev/dotfiles/internal/controller"
)

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, in io.Reader, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("bootstrap-controller", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var shellPath string
	var onlyCSV string
	var prompt bool
	var protocolVersion int
	fs.StringVar(&shellPath, "shell", "", "path to bootstrap/install.sh")
	fs.StringVar(&onlyCSV, "only", "", "comma-separated action ids to pass through to shell")
	fs.BoolVar(&prompt, "prompt", false, "prompt for action selection instead of auto-selecting all")
	fs.IntVar(&protocolVersion, "protocol-version", controller.ProtocolVersion, "controller protocol version")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	resolvedShell, err := resolveShellPath(shellPath)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}

	adapter := controller.NewAdapter(resolvedShell)
	adapter.ProtocolVersion = protocolVersion
	selected := splitCSV(onlyCSV)

	handshake, err := adapter.Handshake(ctx)
	if err != nil {
		fmt.Fprintf(stderr, "Go controller unavailable (%v); falling back to shell bootstrap.\n", err)
		return runFallback(ctx, adapter, selected, stdout, stderr)
	}

	choices, err := adapter.LoadChoices(ctx)
	if err != nil {
		fmt.Fprintf(stderr, "Go controller could not load shell choices (%v); falling back to shell bootstrap.\n", err)
		return runFallback(ctx, adapter, selected, stdout, stderr)
	}

	if len(selected) == 0 {
		selected, err = chooseActions(choices.Actions, prompt, in, stdout)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
	}

	fmt.Fprintf(stdout, "Go controller handshake ok (protocol %d)\n", handshake.ProtocolVersion)
	printChoices(stdout, choices.Actions, selected)

	output, err := adapter.Apply(ctx, selected)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	if len(output) > 0 {
		if _, err := stdout.Write(output); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
	}
	return 0
}

func runFallback(ctx context.Context, adapter *controller.Adapter, selected []string, stdout, stderr io.Writer) int {
	output, err := adapter.Fallback(ctx, selected)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	if len(output) > 0 {
		if _, err := stdout.Write(output); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
	}
	return 0
}

func resolveShellPath(explicit string) (string, error) {
	root, err := dotfilesRootResolver()
	if err != nil {
		return "", fmt.Errorf("locate dotfiles root: %w", err)
	}

	var candidate string
	switch {
	case explicit != "":
		candidate = explicit
	case os.Getenv("BOOTSTRAP_SHELL_PATH") != "":
		candidate = os.Getenv("BOOTSTRAP_SHELL_PATH")
	default:
		candidate = filepath.Join(root, "bootstrap", "install.sh")
	}

	return validateShellPath(root, candidate)
}

// dotfilesRootResolver returns the absolute path to the dotfiles root, which
// is the directory that must contain every allowed shell path.
//
// The default resolver derives the root from the location of the running
// binary (assumed to live at <root>/cmd/bootstrap-controller/). Tests can
// override the variable to point to a fixture directory.
var dotfilesRootResolver = defaultDotfilesRoot

func defaultDotfilesRoot() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.Dir(filepath.Dir(filepath.Dir(exe))), nil
}

// validateShellPath enforces the shell contract safety rules: the resolved
// path must live inside the dotfiles tree, must be a regular file, must be
// executable, and must not be writable by group or other.
func validateShellPath(trustedRoot, candidate string) (string, error) {
	abs, err := filepath.Abs(candidate)
	if err != nil {
		return "", fmt.Errorf("resolve absolute path: %w", err)
	}

	resolved, err := filepath.EvalSymlinks(abs)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", fmt.Errorf("shell path does not exist: %s", candidate)
		}
		return "", fmt.Errorf("evaluate symlinks for %s: %w", candidate, err)
	}

	absRoot, err := filepath.Abs(trustedRoot)
	if err != nil {
		return "", fmt.Errorf("resolve trusted root: %w", err)
	}
	resolvedRoot := absRoot
	if r, err := filepath.EvalSymlinks(absRoot); err == nil {
		resolvedRoot = r
	}

	rel, err := filepath.Rel(resolvedRoot, resolved)
	if err != nil {
		return "", fmt.Errorf("compute relative path: %w", err)
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("shell path %q is outside the trusted dotfiles root", candidate)
	}

	info, err := os.Stat(resolved)
	if err != nil {
		return "", fmt.Errorf("stat shell path: %w", err)
	}
	if !info.Mode().IsRegular() {
		return "", fmt.Errorf("shell path %q is not a regular file", resolved)
	}
	if info.Mode().Perm()&0o111 == 0 {
		return "", fmt.Errorf("shell path %q is not executable", resolved)
	}
	if runtime.GOOS != "windows" {
		if info.Mode().Perm()&0o022 != 0 {
			return "", fmt.Errorf("shell path %q is writable by group or others", resolved)
		}
	}

	return resolved, nil
}

func splitCSV(value string) []string {
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			result = append(result, part)
		}
	}
	return result
}

func chooseActions(actions []controller.Choice, prompt bool, in io.Reader, out io.Writer) ([]string, error) {
	ids := make([]string, 0, len(actions))
	if !prompt {
		for _, action := range actions {
			ids = append(ids, action.ID)
		}
		return ids, nil
	}

	for i, action := range actions {
		fmt.Fprintf(out, "%d) %s [%s] %s\n", i+1, action.ID, action.Group, action.Status)
	}
	fmt.Fprint(out, "Select actions (comma-separated ids or numbers, blank = all): ")
	line, err := bufio.NewReader(in).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return nil, err
	}
	line = strings.TrimSpace(line)
	if line == "" {
		for _, action := range actions {
			ids = append(ids, action.ID)
		}
		return ids, nil
	}

	index := map[string]string{}
	for i, action := range actions {
		index[fmt.Sprintf("%d", i+1)] = action.ID
		index[action.ID] = action.ID
	}
	for _, token := range strings.Split(line, ",") {
		token = strings.TrimSpace(token)
		if token == "" {
			continue
		}
		if id, ok := index[token]; ok {
			ids = append(ids, id)
		}
	}
	if len(ids) == 0 {
		for _, action := range actions {
			ids = append(ids, action.ID)
		}
	}
	return ids, nil
}

func printChoices(out io.Writer, actions []controller.Choice, selected []string) {
	selectedSet := map[string]struct{}{}
	for _, id := range selected {
		selectedSet[id] = struct{}{}
	}
	fmt.Fprintln(out, "Shell-backed choices:")
	for _, action := range actions {
		marker := " "
		if _, ok := selectedSet[action.ID]; ok {
			marker = "*"
		}
		fmt.Fprintf(out, "%s %s (%s, %s)\n", marker, action.ID, action.Group, action.Privilege)
	}
}
