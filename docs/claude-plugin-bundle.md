# Alera Plugin For Claude Web

## Independent Distribution

`landing/claude-plugin/` owns the Claude manifest, HTTP MCP config, web setup skill, and README. `landing/src/lib/claude-plugin-bundle.ts` packages those allowlisted inputs, the existing Alera logo and license, and the maintained `edge/skills/` catalog. It adapts reference loading and adds Claude web guidance only in generated Claude copies. It does not change shared skills, OpenAI metadata, or the original builder. Claude and ChatGPT versions are independent.

Run `cd landing` followed by `bun run package:claude-plugin`. The default output is `build/claude-plugin/`: `alera-claude-plugin.zip`, identical ZIP bytes named `alera-claude.plugin`, one checksum per filename, and the extracted `alera/` directory. The archive has `.claude-plugin/plugin.json` directly at its root. `bun run build` serves both formats and checksums under `/downloads/`; the Landing workflow uploads them in a separate `alera-claude-plugin` artifact. No GitHub release mutation is needed for this static website distribution. Vercel must include files outside the landing root, just as the existing ChatGPT builder requires.

## Official Compatibility Findings

Documentation verified on 2026-10-10:

| Claim | Verified behavior and source |
| --- | --- |
| Web chat support | Paid Pro, Max, Team, and Enterprise plans can add and use plugins in web chat. Skills and commands work in chat. [Help Center](https://support.claude.com/en/articles/13837440-use-plugins-in-claude) |
| Upload | Customize > Plugins > Add > Upload plugin accepts `.zip` or `.plugin`, with exactly one `.claude-plugin/plugin.json` at archive root or within one top-level folder. [Web instructions](https://claude.com/docs/plugins/overview), [Plugins API upload requirements](https://platform.claude.com/docs/en/manage-claude/plugins-api#upload-requirements) |
| Remote MCP | `.mcp.json` with `mcpServers.alera.type` set to `http` and a fixed public HTTPS URL is listed on the web plugin's Connectors tab. The user must add and connect it separately. Local MCP, hooks, and subagents do not execute in chat. [Web build reference](https://claude.com/docs/plugins/build), [Platform support](https://claude.com/docs/plugins/platform-support) |
| OAuth | Web connectors support CIMD or DCR discovered from the server. CIMD requires `client_id_metadata_document_supported: true` plus public token auth method `none`. S256 PKCE is required. Web callback is `https://claude.ai/api/mcp/auth_callback`. [Connector authentication](https://claude.com/docs/connectors/building/authentication) |
| Scope selection | Web requests scopes from a `scope` challenge, otherwise protected resource metadata. Code's `oauth.scopes`, `callbackPort`, and metadata override are documented in Code docs, not as web plugin settings. The package omits them rather than promising web enforcement. [Web authentication](https://claude.com/docs/connectors/building/authentication), [Code MCP](https://code.claude.com/docs/en/mcp) |
| Metadata and assets | `displayName`, version, description, author, license, and normal skill files are supported. `icon`, `documentationUrl`, `supportUrl`, `privacyPolicyUrl`, and `termsOfServiceUrl` are documented directory listing fields. This does not prove custom-upload icon rendering or directory approval. [Manifest reference](https://code.claude.com/docs/en/plugins-reference) |
| API publication | Plugins API is beta, Enterprise-only, unavailable to Claude Console organizations and HIPAA-ready organizations, and requires scoped Admin API keys. It is not required for manual web upload and was not invoked. [Plugins API](https://platform.claude.com/docs/en/manage-claude/plugins-api) |

## OAuth Observation And Limits

Read-only inspection of the public Alera metadata confirmed resource `https://api.alera.build/v1/mcp`, issuer `https://api.alera.build`, CIMD support, token authentication `none`, a DCR registration endpoint, S256 PKCE, authorization-code and refresh-token grants. The protected resource and authorization metadata advertise `mcp:read`, `mcp:execute`, and `mcp:admin`. Therefore a URL-only web plugin cannot promise read/execute-only consent. No scope, grant, credential, callback allowlist, or runtime permission was modified. Metadata availability proves discovery prerequisites only, not that Claude's hosted client completes authorization, token exchange, refresh, or runtime calls.

The package does not use OpenAI `extensions.com.openai.auth`, invent a Claude web auth object, pin a client id, carry a bearer header, or embed a secret. Alera runtime access remains controlled by user consent and MCP Control. Uploading the plugin does not itself authorize anything. Organization policies may require an Owner to add the connector or may block a custom upload.

## Validation

Automated tests extract all files, check the manifest and resource links, parse each skill's YAML frontmatter, preserve every source reference, verify Claude-only adaptations, reject accidental local/Code/OpenAI components, check upload file/path/size constraints, and compare deterministic checksums across time zones. The original ChatGPT archive's baseline hash is pinned for this compatibility change. Playwright downloads both archives and checksums from the built website and verifies the guide, mobile/desktop overflow, and accessibility.

Local validation passed: 114 landing unit tests, TypeScript typecheck, production Astro build (56 pages), and 63 Playwright tests. Claude Code 2.1.296 passed `claude plugin validate ./build/claude-plugin/alera --strict`, with advisory text suggesting a CLI marketplace install line; that is intentionally unnecessary for this web upload package. No CLI installation was performed. A CLI install is never evidence of a Claude web installation: sync is one-way from the web account to Code. Both Claude archive formats were 72,660 bytes with SHA-256 `696bd234f1ce0d731a4abecae67f3171910f8b2064cd2af7c16646aaf1b044e4`. The ChatGPT ZIP remained 91,316 bytes with SHA-256 `4f1fedc3116746ebdc0dc006bab198520bc205660b0fb6242bd0f80305811b91`.

An unauthenticated `initialize` request returned HTTP 401 with `WWW-Authenticate: Bearer resource_metadata="https://api.alera.build/.well-known/oauth-protected-resource/v1/mcp", scope="mcp:read mcp:execute mcp:admin"`. This verifies discovery and the advertised requested scopes without authenticating or creating a grant.

Remaining real-account acceptance steps: upload either archive in Claude web; confirm all five skills appear; add/connect Alera from the plugin's Connectors tab; inspect the real consent scopes and chosen runtimes; call `list_runtimes` and read-only `list_projects`; reconnect and verify refresh separately. These actions are not performed by packaging tests. Do not automatically create grants or elevate permissions to prove setup.
