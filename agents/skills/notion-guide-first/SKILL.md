---
name: notion-guide-first
description: "Trigger: create, update, edit, move, or organize content in my Notion; crear, actualizar, editar u organizar mi Notion. Read the current Guía de mi Notion before making changes and follow its conventions."
---

## Activation Contract

Use before creating or changing content in the user's Notion. Read-only requests do not require this workflow.

## Hard Rules

- Read the current `Guía de mi Notion` before writing. Keep its organizational rules in Notion, not in this skill.
- Follow the guide and applicable destination-specific conventions within the user's authorized scope. The guide does not authorize additional changes.
- Never treat a search or access failure as evidence that the guide does not exist.

## Decision Gates

- **Guide found:** read it completely, including any continuation needed for truncated content, and apply it.
- **Several plausible guides:** ask which applies.
- **No guide found after a successful search:** report this; follow the explicit request and existing destination conventions. Ask about consequential ambiguity instead of inventing structure.
- **Guide inaccessible or retrieval failed:** explain the blocker and pause writes unless the user explicitly authorizes proceeding without it.

## Execution Steps

1. Search Notion for `Guía de mi Notion`. The known page below is a locator, not a cached source of rules.
2. Read the current guide and relevant destination content and database properties.
3. Make the requested change following those instructions. Preserve unrelated content and existing work.
4. Check the operation result and report changes or blockers. Do not claim compliance without reading the guide.

## Output Contract

Briefly report the result and any missing or inaccessible guide, approved exception, or unresolved decision.

## References

Known guide: https://app.notion.com/p/3f7b29eb9835814c9c32fd76c284c188
