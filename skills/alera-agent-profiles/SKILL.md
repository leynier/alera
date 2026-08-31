---
name: alera-agent-profiles
description: Design, create, update, validate, reorder, or remove Alera Agent Profiles, including current model research, Managed configuration, quota-aware routing, and launch smoke tests. Use for Agent Profile catalog work, not ordinary agent dispatch or orchestration.
---

# Alera Agent Profiles

## Purpose

Build a small, evidence-backed catalog of launch recipes that Alera and its coordinators can route correctly. An Agent Profile combines an adapter, launch mode, model and adapter options, a routing description, an optional custom prompt, and a quota group.

Use the top-level `alera agent-profile ...` commands to administer profiles. `alera orchestration agent-profiles` is read-only coordinator discovery and must not be used for mutations.

## Workflow

1. Inspect the active runtime and existing catalog with `alera runtime status`, `alera agent-profile --json list`, and `alera agent-profile --json show --profile-name "<profile-name>"`.
2. Discover the actual installed CLIs, versions, models, and supported flags. Prefer CLI model listings and `--help` over remembered slugs. Do not assume two versions of one provider accept the same interactive flags.
3. If the user asks for a proposal or model selection, research current model capabilities before changing profiles. Compare coding quality, terminal and long-horizon behavior, speed, context, multimodality, reliability, and quota cost. Prefer primary model and CLI documentation for factual claims; use independent benchmarks only as comparative evidence with their harness and date stated.
4. Convert the evidence into roles. Remove profiles dominated on both quality and cost unless they provide a distinct harness, quota pool, modality, or operational role.
5. Present the proposed catalog before mutation unless the user explicitly asked to create or update it. Include name, adapter, model, effort, launch mode, quota group, protections, description, custom prompt, and command preview.
6. Prefer Managed mode when Alera can express the needed flags. Use Command mode only for an unsupported launch shape, and explain what Managed cannot represent.
7. Apply only the approved mutations. Use `--expected-revision` for scripted updates after reading a profile. Pass `--confirm-reduced-protections` only when the user approved the protection reduction.
8. Re-read the catalog and verify the persisted configuration and generated command.
9. When requested, run one bounded smoke test per changed profile with a prompt that names the selected model and forbids file edits. Verify process startup, model selection, response, tab existence, and agent status separately.

For current Managed keys, mutation examples, and adapter-specific launch traps, read [references/managed-profiles.md](references/managed-profiles.md).

## Catalog Design

- Treat `description` as routing policy, not marketing copy. Say what the profile should own, when it should not be selected, and any same-quota exclusion that matters.
- Set `quotaGroup` to the real shared subscription or usage pool. Different models, providers, or harnesses that drain the same pool belong to the same group. Profiles in the same group are not useful quota fallbacks for one another.
- Distinguish a model from its harness. The same model in two CLIs may have different tools, effort scaling, latency, permissions, and quota pools.
- Prefer a Pareto frontier: a high-quality profile, a cheap or fast profile, and specialists whose role or independent quota justifies them. Do not keep a middle tier merely because it exists.
- Use custom prompts only for durable role constraints that the model or description cannot carry, such as an adversarial review contract. Do not repeat generic repository instructions.
- Keep model research and exact slugs current. A previous catalog is evidence about user preferences, not proof that models, flags, or quotas are unchanged.

## Safety And Authorization

- Listing, research, previews, and launch diagnostics are read-only. Creating, updating, reordering, removing, or launching profiles changes runtime state and requires the user's request.
- Never infer approval for YOLO, bypass, trust, disabled sandbox, or auto-approval settings from a request to create a profile. Surface the reduced protection and require explicit intent.
- Before removal, run `removal-impact`; remove only with `--confirm` after reporting affected references.
- Preserve unrelated profiles and their order. Reorder requires every current profile id exactly once.
- Do not edit the runtime database or send private socket requests when the supported CLI can perform the operation.

## Validation Rules

- A tab existing does not prove that Alera recognized it as an agent. Check both the tab and terminal agent metadata.
- A model's self-reported name is weak evidence. Prefer the persisted profile, generated command, CLI footer or model indicator, and process arguments.
- If a CLI silently falls back to another model, treat the smoke test as failed even if it answers.
- If agent status is missing, inspect the integration path independently from model launch. For wrapper-based integrations such as Cursor, confirm the wrapper or required plugin argument actually reached the child process after shell startup changed `PATH`.
- Record each profile as passed, failed, or passed with a specific status-integration issue. Do not collapse those outcomes into a single launch result.

## Reporting

Return a compact table of proposed or persisted profiles, followed by validation evidence and unresolved issues. Separate catalog correctness, model selection, quota routing, and hook/status integration so one success does not hide another failure.
