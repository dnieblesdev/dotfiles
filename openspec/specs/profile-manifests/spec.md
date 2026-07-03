# Delta for profile-manifests

## ADDED Requirements

### Requirement: Declarative profile manifests
The system MUST define profiles as declarative manifests that select modules without installing packages or runtimes.

#### Scenario: Profile selects modules
- GIVEN a profile manifest exists
- WHEN the profile is evaluated
- THEN it selects the intended modules declaratively
- AND it does not trigger installation behavior

#### Scenario: Profiles remain non-provisioning
- GIVEN a profile references optional configuration modules
- WHEN the profile is applied
- THEN it affects only dotfiles selection and linking
- AND it does not provision software

### Requirement: Safe manifest evaluation
The system MUST treat `.sh` profile manifests as restricted shell-data files, not executable provisioning scripts.

#### Scenario: Assignment-only syntax is accepted
- GIVEN a profile manifest contains only allowed variable assignments for profile metadata and module selection
- WHEN the manifest is loaded
- THEN the loader validates the manifest before using it
- AND it accepts the declared data without running provisioning behavior

#### Scenario: Commands and functions are rejected
- GIVEN a profile manifest contains command substitutions, function definitions, aliases, shell control flow, external command invocations, file mutations, package installation, or provisioning logic
- WHEN the manifest is loaded
- THEN the loader rejects the manifest as invalid
- AND none of the rejected commands or functions execute

#### Scenario: Profiles are not executable provisioning
- GIVEN a reader inspects profile documentation
- WHEN they look for profile responsibilities
- THEN profiles are described as safe declarative module selection data
- AND they are not described as arbitrary executable setup scripts
