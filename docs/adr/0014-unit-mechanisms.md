# ADR 0014: Unit mechanisms – declared in the catalog, carried by the model as metadata

- **Status**: accepted
- **Date**: 2026-10-24

## Context

How a vehicle animates is a property of the real vehicle (the Homar-K traverses fully and stows its launcher facing the rear, the Uragan has limited traverse and stabilisers), not of its class. Animation code keyed on pivot names alone cannot know the parameters, and a catalog that doesn't match the model is not authoritative.

## Decision

- The unit catalog entry declares `mechanisms` (id -> params, registry `docs/design/units/mechanisms.json`).
- The model file copies them into a `MECHANISMS` constant and stores them on the built model node with `ModelParts.declare_mechanisms` (metadata `mechanisms`). `UnitModels.mechanisms / mechanism / has_mechanism` read them. Pivots activate a mechanism, the metadata parameterises it.
- A test (`tests/unit/test_unit_mechanisms.gd`) keeps model, catalog and registry in agreement: metadata equals the catalog, implemented mechanisms have their pivots, and a model owning the pivot of an undeclared mechanism fails. Drift after a catalog edit fails until the model file is updated.

## Alternatives considered

- **Per-class code** (all `mlrs` animate alike): wrong for units of one class that differ.
- **The game reads the catalog**: ties the runtime to `docs/`, which is not exported and is edited by a tool.
- **Constants looked up by unit id** in `UnitModels`: the pose functions only get the node tree; metadata also survives `ModelParts.cached` copies and keeps parameters next to the geometry they shape.

## Consequences

Changing a parameter in the catalog tool needs a one-line edit of the model file (or `/model-unit <id>`) before `tools/check.sh` passes again; this is the intended signal.
