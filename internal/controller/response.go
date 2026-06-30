package controller

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
)

var (
	ErrUnsupportedProtocol = errors.New("shell controller protocol mismatch")
	ErrInvalidPayload      = errors.New("unexpected shell payload")
)

func decodeStrict(data []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return err
	}
	var extra json.RawMessage
	if err := dec.Decode(&extra); err != io.EOF {
		return fmt.Errorf("%w: trailing data", ErrInvalidPayload)
	}
	return nil
}

func ValidateHandshakeResponse(resp HandshakeResponse) error {
	if resp.ProtocolVersion != ProtocolVersion {
		return fmt.Errorf("%w: got %d want %d", ErrUnsupportedProtocol, resp.ProtocolVersion, ProtocolVersion)
	}
	if resp.Status != "ok" {
		return fmt.Errorf("%w: handshake status %q", ErrInvalidPayload, resp.Status)
	}
	if resp.ShellContract == "" || resp.ShellContractVersion == 0 {
		return fmt.Errorf("%w: incomplete shell contract metadata", ErrInvalidPayload)
	}
	if resp.BootstrapSchemaVersion == 0 || resp.BootstrapCatalogVersion == 0 {
		return fmt.Errorf("%w: missing bootstrap version metadata", ErrInvalidPayload)
	}
	if len(resp.SupportedShellCommands) == 0 {
		return fmt.Errorf("%w: no supported shell commands advertised", ErrInvalidPayload)
	}
	return nil
}

func ValidateListResponse(resp ListResponse) error {
	if resp.SchemaVersion == 0 || resp.CatalogVersion == 0 {
		return fmt.Errorf("%w: missing schema metadata", ErrInvalidPayload)
	}
	if resp.CatalogHash == "" {
		return fmt.Errorf("%w: missing catalog hash", ErrInvalidPayload)
	}
	if len(resp.Actions) == 0 {
		return fmt.Errorf("%w: no actions returned", ErrInvalidPayload)
	}
	seen := map[string]struct{}{}
	for _, action := range resp.Actions {
		if action.ID == "" || action.Label == "" {
			return fmt.Errorf("%w: action metadata incomplete", ErrInvalidPayload)
		}
		if _, ok := seen[action.ID]; ok {
			return fmt.Errorf("%w: duplicate action %q", ErrInvalidPayload, action.ID)
		}
		seen[action.ID] = struct{}{}
	}
	return nil
}
