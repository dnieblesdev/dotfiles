package controller

const ProtocolVersion = 1

type HandshakeRequest struct {
	ProtocolVersion int    `json:"protocol_version"`
	Request         string `json:"request"`
	Client          string `json:"client,omitempty"`
	Intent          string `json:"intent,omitempty"`
}

type HandshakeResponse struct {
	ProtocolVersion        int      `json:"protocol_version"`
	Status                 string   `json:"status"`
	ShellContract          string   `json:"shell_contract"`
	ShellContractVersion   int      `json:"shell_contract_version"`
	BootstrapSchemaVersion int      `json:"bootstrap_schema_version"`
	BootstrapCatalogVersion int      `json:"bootstrap_catalog_version"`
	SupportedShellCommands []string `json:"supported_shell_commands"`
	Error                  string   `json:"error,omitempty"`
	ExpectedProtocol       int      `json:"expected_protocol_version,omitempty"`
	ReceivedProtocol       int      `json:"received_protocol_version,omitempty"`
}

type ListContext struct {
	TargetUser       string `json:"target_user"`
	TargetHome       string `json:"target_home"`
	EffectiveUser    string `json:"effective_user"`
	ExecutionContext string `json:"execution_context"`
	Frontend         string `json:"frontend"`
}

type Choice struct {
	ID        string   `json:"id"`
	Label     string   `json:"label"`
	Group     string   `json:"group"`
	Privilege string   `json:"privilege"`
	Deps      []string `json:"deps"`
	Status    string   `json:"status"`
}

type ListResponse struct {
	SchemaVersion int        `json:"schema_version"`
	CatalogVersion int       `json:"catalog_version"`
	CatalogHash   string     `json:"catalog_hash"`
	Context       ListContext `json:"context"`
	Actions       []Choice   `json:"actions"`
}
