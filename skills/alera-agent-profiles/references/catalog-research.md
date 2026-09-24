# Catalog Research And Design

Research when the request includes model selection, catalog design, or changing launch capabilities. A narrowly specified maintenance edit does not need this workflow.

## Research And Apply

Inspect the existing catalog and relevant installed CLI versions, model listings, and flags. Use current primary model and CLI documentation for factual claims. Independent benchmarks can supply comparative evidence when their harness and date are stated. Compare the capabilities and costs that matter to the requested roles, rather than researching every provider by default.

For a proposal-only request, present the catalog and stop. For authorized implementation, apply the requested changes without another approval round. Include the model, effort, adapter, launch mode, quota group, protections, routing description, custom prompt, and command preview where relevant to the decision. Recommend removing dominated profiles only within the requested redesign scope; do not delete unrelated profiles.

Prefer Managed mode when it expresses the required flags; use Command mode for unsupported launch shapes and explain the limitation. Use observed revisions for scripted updates, then re-read persisted configuration and generated commands. Protection reductions still need explicit authorization.

Read [managed profiles](managed-profiles.md) for configuration keys and adapter traps. Read [launch validation](launch-validation.md) only for requested smoke tests or launch diagnosis.

## Catalog Design

- Treat `description` as routing policy, not marketing copy. Say what the profile should own, when it should not be selected, and any same-quota exclusion that matters.
- Set `quotaGroup` to the real shared subscription or usage pool. Different models, providers, or harnesses that drain the same pool belong to the same group. Profiles in the same group are not useful quota fallbacks for one another.
- Distinguish a model from its harness. The same model in two CLIs may have different tools, effort scaling, latency, permissions, and quota pools.
- Prefer a Pareto frontier: a high-quality profile, a cheap or fast profile, and specialists whose role or independent quota justifies them. Do not keep a middle tier merely because it exists.
- Use custom prompts only for durable role constraints that the model or description cannot carry, such as an adversarial review contract. Do not repeat generic repository instructions.
- Keep model research and exact slugs current. A previous catalog is evidence about user preferences, not proof that models, flags, or quotas are unchanged.

## Reporting

Return a compact table of proposed or persisted profiles, followed by validation evidence and unresolved issues. Separate catalog correctness, model selection, quota routing, and hook/status integration so one success does not hide another failure.
