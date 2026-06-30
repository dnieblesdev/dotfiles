# project-source-of-truth Specification

## Purpose

This capability defines the documentation system as the authoritative source for project intent, boundaries, and durable decisions. It MUST prevent readers from treating README, scattered docs, or runtime code as the primary architecture authority.

## Requirements

### Requirement: Entry-map README

The documentation system MUST treat `README.md` as an entry map that points to authoritative docs, not as the source of architectural truth.

#### Scenario: Reader starts from README
- GIVEN a contributor opens the repository root
- WHEN they read `README.md`
- THEN they can find links to the authoritative docs
- AND they do not need README to restate the full architecture

#### Scenario: README conflicts with deeper docs
- GIVEN a README summary and a deeper authority document disagree
- WHEN a reader resolves the conflict
- THEN the deeper authority document wins

### Requirement: Stable source-of-truth document

The documentation system MUST maintain a stable vision/source-of-truth document that defines project purpose, boundaries, non-goals, and authority hierarchy.

#### Scenario: New contributor needs orientation
- GIVEN a contributor needs the project intent
- WHEN they read the source-of-truth document
- THEN they can identify purpose, boundaries, and non-goals

#### Scenario: Scope dispute arises
- GIVEN a proposed change blurs the project boundary
- WHEN the source-of-truth document is consulted
- THEN it clarifies whether the change is in scope

### Requirement: Shell-first bootstrap contract

The documentation system MUST state that shell-based installer behavior is canonical and that the Go/TUI surface is optional frontend behavior.

#### Scenario: Install workflow is documented
- GIVEN a reader wants to understand bootstrap authority
- WHEN they read the bootstrap contract
- THEN they see shell-first canonicality stated explicitly
- AND they see the Go/TUI path described as optional

#### Scenario: Frontend behavior diverges
- GIVEN the frontend and shell behavior differ in description
- WHEN authority is determined
- THEN the shell contract is treated as canonical

### Requirement: Roadmap and decision records boundary

The documentation system MUST separate active or deferred work in the roadmap from stable policy, and MUST use decision records for durable architectural decisions when needed.

#### Scenario: Work is still changing
- GIVEN a topic is actively being explored or deferred
- WHEN it is documented
- THEN it belongs in the roadmap, not in stable policy

#### Scenario: Durable decision is made
- GIVEN an architectural choice is unlikely to change
- WHEN the decision is recorded
- THEN it is captured in a decision record

### Requirement: Anti-drift links

The documentation system MUST link authority boundaries and changed areas so readers can detect and avoid documentation drift.

#### Scenario: A doc changes scope
- GIVEN a document changes a boundary or responsibility
- WHEN the change is published
- THEN the affected authority links are updated
- AND readers can trace which doc is authoritative

#### Scenario: A stale page is found
- GIVEN a page is no longer authoritative
- WHEN a contributor reviews the doc set
- THEN the page points to the current source of truth or is marked as non-authoritative
