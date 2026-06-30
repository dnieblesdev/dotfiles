package controller

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type Adapter struct {
	ShellPath       string
	ProtocolVersion int
}

func NewAdapter(shellPath string) *Adapter {
	return &Adapter{ShellPath: shellPath, ProtocolVersion: ProtocolVersion}
}

func (a *Adapter) Handshake(ctx context.Context) (HandshakeResponse, error) {
	request := HandshakeRequest{
		ProtocolVersion: a.ProtocolVersion,
		Request:         "handshake",
		Client:          "bootstrap-controller",
		Intent:          "tui",
	}
	payload, err := json.Marshal(request)
	if err != nil {
		return HandshakeResponse{}, err
	}
	stdout, _, runErr := a.run(ctx, []string{"controller"}, payload)
	var response HandshakeResponse
	if err := decodeStrict(stdout, &response); err != nil {
		if runErr != nil {
			return HandshakeResponse{}, runErr
		}
		return HandshakeResponse{}, err
	}
	if response.Status == "unsupported" {
		return response, ErrUnsupportedProtocol
	}
	if err := ValidateHandshakeResponse(response); err != nil {
		return HandshakeResponse{}, err
	}
	if runErr != nil {
		return HandshakeResponse{}, runErr
	}
	return response, nil
}

func (a *Adapter) LoadChoices(ctx context.Context) (ListResponse, error) {
	var response ListResponse
	if err := a.callShell(ctx, []string{"list", "--format", "json"}, nil, &response); err != nil {
		return ListResponse{}, err
	}
	if err := ValidateListResponse(response); err != nil {
		return ListResponse{}, err
	}
	return response, nil
}

func (a *Adapter) Apply(ctx context.Context, only []string) ([]byte, error) {
	args := []string{"apply"}
	if len(only) > 0 {
		args = append(args, "--only", strings.Join(only, ","))
	}
	stdout, _, err := a.run(ctx, args, nil)
	return stdout, err
}

func (a *Adapter) Fallback(ctx context.Context, only []string) ([]byte, error) {
	return a.Apply(ctx, only)
}

func (a *Adapter) callShell(ctx context.Context, args []string, stdin []byte, out any) error {
	stdout, _, err := a.run(ctx, args, stdin)
	if err != nil {
		return err
	}
	return decodeStrict(stdout, out)
}

func (a *Adapter) callJSON(ctx context.Context, args []string, req any, out any) error {
	payload, err := json.Marshal(req)
	if err != nil {
		return err
	}
	stdout, _, err := a.run(ctx, args, payload)
	if err != nil {
		return err
	}
	return decodeStrict(stdout, out)
}

func (a *Adapter) run(ctx context.Context, args []string, stdin []byte) ([]byte, string, error) {
	if a.ShellPath == "" {
		return nil, "", fmt.Errorf("missing shell path")
	}

	cmd := exec.CommandContext(ctx, a.ShellPath, args...)
	if stdin != nil {
		cmd.Stdin = bytes.NewReader(stdin)
	}
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	cmd.Env = SanitizeShellEnv()
	err := cmd.Run()
	return stdout.Bytes(), stderr.String(), err
}

// SanitizeShellEnv returns a deterministic environment for the shell contract.
//
// The shell contract is fully self-contained and does not need the Go process
// environment. We pass only the minimum required for the shell to function and
// honor BOOTSTRAP_* variables that the shell contract may use. Every other
// variable (secrets, temp tokens, debug flags, language-specific leaks) is
// dropped on purpose to keep the shell boundary explicit.
func SanitizeShellEnv() []string {
	keep := map[string]struct{}{
		"HOME": {},
		"USER": {},
		"PATH": {},
	}
	env := make([]string, 0, 8)
	for _, kv := range os.Environ() {
		name, _, _ := strings.Cut(kv, "=")
		if _, ok := keep[name]; ok {
			env = append(env, kv)
			continue
		}
		if strings.HasPrefix(name, "BOOTSTRAP_") {
			env = append(env, kv)
		}
	}
	return env
}
