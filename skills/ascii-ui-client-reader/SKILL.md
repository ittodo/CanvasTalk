---
name: ascii-ui-client-reader
description: Convert ASCII canvas wireframes and node YAML hierarchies into implementable client UI (especially Flutter) with accurate layout, component-specific properties, and overlay/standalone page composition. Use when requests include ASCII UI text, exported canvas YAML, or "build this screen from ASCII" tasks, and when Codex must turn design artifacts into runnable UI code.
---

# ASCII UI Client Reader

## Overview

Turn fixed-width ASCII UI and node hierarchy data into concrete client UI implementation decisions and code. Prefer YAML hierarchy as source of truth for component kind and properties, and use ASCII for spatial intent and visual grouping.

## Required Inputs

- Collect `ascii_text` for each page in fenced code blocks.
- Collect node hierarchy YAML per page with `id`, `kind`, `x`, `y`, `w`, `h`, `props`, and child relations.
- Collect page metadata: page name, mode (`standalone` or `overlay`), and overlay parent/anchor when applicable.
- Confirm target runtime (`Flutter` by default) and output style (`single screen`, `multi page`, or `component library`).

## Conversion Workflow

1. Normalize geometry.
- Treat ASCII as a monospaced grid.
- Preserve spaces and line endings exactly.
- Build a grid coordinate system where `(x,y)` starts at top-left, width is character cells, and height is lines.
- Use YAML coordinates when ASCII and YAML disagree, and report mismatches briefly.

2. Build semantic tree.
- Reconstruct parent-child hierarchy from YAML.
- Keep sibling order as z-order (later sibling is on top unless input says otherwise).
- Resolve repeated hit regions by selecting topmost node first and cycling to deeper layers when requested.

3. Resolve page composition.
- Implement `standalone` pages as isolated roots.
- Implement `overlay` pages as additional layers over a parent page.
- Anchor overlay root coordinates against parent origin `(0,0)`.
- Keep parent visible unless overlay `props` indicate modal behavior.

4. Map kinds to concrete widgets.
- Apply kind-specific mapping and props from `references/flutter-kind-props.md`.
- Refuse to collapse all kinds to a generic rectangle template.
- Generate specialized property editors/constructors for each kind.

5. Generate output artifacts.
- Produce runnable UI code files.
- Produce a YAML manifest that preserves hierarchy and props.
- Produce a short assumptions list for ambiguous areas.

## Output Contract

- Return created or edited file list first.
- Keep geometry deterministic; avoid auto-resizing unless explicitly requested.
- Keep node IDs stable across regenerations.
- Include copy-ready ASCII export and hierarchy YAML when round-trip support is requested.

## Validation Checklist

- Verify every YAML node appears exactly once in the implementation tree.
- Verify required kind-specific properties are present.
- Verify overlay parent references exist.
- Verify duplicate page names are rejected safely.
- Verify user-requested keyboard shortcuts do not conflict with existing bindings.

## References

- Read `references/flutter-kind-props.md` when generating Flutter widgets and property editors.
