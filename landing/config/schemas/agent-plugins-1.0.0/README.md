# Official Agent Plugins 1.0.0 Schemas

Unmodified copies fetched on 2026-10-10 from https://agent-plugins.org/schemas/1.0.0/plugin.schema.json and https://agent-plugins.org/schemas/1.0.0/mcp.schema.json. Both match the files in the official https://github.com/agentplugins/agent-plugins-spec repository at commit `ff8ab5e392cc87bd88d87c060815a87490e51003`. Schemas are Apache-2.0 licensed; the upstream license is included as `LICENSE.txt`. They are validation inputs only and are not part of any downloadable plugin.

- `plugin.schema.json`: SHA-256 `0a4aad95ce337878ad38802ebf0daa3fde76abe3f65400c86bcbb1ec0b3ab883`
- `mcp.schema.json`: SHA-256 `6539175bfcdf43085855183e86da40ea94b166547a72b47ae9a0a390516d3acb`

Ajv draft 2020-12 validates the actual documents during build and tests without fetching schemas at load time. The normative specification also imposes operational and URL requirements beyond JSON Schema; see the bundle validation and tests. Do not alter these fixtures to make a package pass; update them only from a verified official version and record its provenance.
