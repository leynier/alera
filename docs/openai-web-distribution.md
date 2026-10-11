# Alera On ChatGPT Web

## Outcome And Evidence

Public users must be able to install Alera without entering its MCP URL. A downloaded MCP ZIP does not achieve this in ChatGPT web: [imported MCP declarations are desktop-only, including HTTPS](https://learn.chatgpt.com/docs/enterprise/plugin-management#desktop-only-plugins). This applies to `mcp.json`, `.mcp.json`, and inline forms. It is not evidence of stdio, local tools, or multi-manifest failure.

Inspected the actual privately sent `build/experimental-plugin/alera-combined-experimental.zip` (92167 bytes, SHA-256 `ae85bbba854633a46425efa9dc25fe8e89792af786500eb21584fb72e335e17a`) and separate `landing/dist/downloads/alera-plugin.zip` (91316 bytes, SHA-256 `4f1fedc3116746ebdc0dc006bab198520bc205660b0fb6242bd0f80305811b91`). Both include root `mcp.json`, `.mcp.json`, and a native manifest pointing `mcpServers` at `./.mcp.json`. Both target `https://api.alera.build/v1/mcp`, with no stdio command. OpenAI's rule explains the classification of either package. The user has not identified which of three agents' ZIPs was imported; this is artifact inspection and documented behavior, not reproduction of their session.

The standalone package retains OpenAI CIMD OAuth metadata. The experimental standard MCP configuration has no vendor authentication override. Neither difference avoids the imported-MCP rule. Preserve both and all five production archives; no revised experimental ZIP is sent because no valid ZIP-only web fix has been established.

The user's Claude web import/use report is preliminary positive evidence for an unidentified ZIP. It disproves a categorical claim that competing manifests always fail in Claude web. It does not prove this archive's installation, a complete OAuth flow, or coverage of all packages.

## Public Distribution

[OpenAI's submission workflow](https://developers.openai.com/plugins/deploy/submission) requires a verified publishing identity, permitted organization/project, initial ZIP with MCP, server/domain/OAuth setup, successful required scans, review materials, review, and explicit publication after approval. One MCP server can be connected per plugin. The package's CIMD preference is documented; portal registration and grants remain unperformed.

[Published listings](https://developers.openai.com/plugins/deploy/app-review#publication-and-distribution) are discoverable by name or directory URL. Users install the listing and authenticate their own account, without registering the server URL. Account and workspace policies still apply. Private/workspace use is documented through custom MCP connections; neither that route nor local/GitHub marketplace imports establish an unreviewed public or unlisted web link. No such bypass was found in the reviewed official sources.

Code shipping, website ZIP downloads, and directory publication are separate outcomes. This PR does not upload a draft, register an app, modify authentication, verify a domain, submit for review, or publish.

## Already Registered Apps

Root `.app.json` can reference existing `asdk_app_`, `connector_`, or `templated_apps_` IDs. Portable `plugin.json` points to it through `extensions.com.openai.apps`; the native fallback uses `apps`. [OpenAI's package rules](https://developers.openai.com/plugins/build/plugins#add-openai-specific-metadata) give the inline extension precedence over the entire native overlay. [References](https://learn.chatgpt.com/docs/enterprise/plugin-management#reference-an-existing-app-with-appjson) create neither apps nor permissions.

Repository searches for registered IDs/app mappings returned no Alera ID. A read-only Plugin Management directory lookup for `Alera` returned no entries. These bounded results do not prove that no private or unpublished registration exists. The runtime exposes Alera tools, but tool availability is not evidence of a public listing ID. No private owner connection is reused and no ID is invented. A valid apps-only audience-specific package would require an independently verified app ID, actual audience availability, and no MCP declarations anywhere; it would not replace the portable MCP bundle or solve public distribution using a private connection.

## Publisher Preparation Status

The current 1.0.0 package is preserved, not certified submission-ready. Its 39-character `shortDescription` exceeds the [30-character public-submission limit](https://developers.openai.com/plugins/deploy/submission#listing-metadata). A separately authorized publication version must shorten it; this does not fix desktop-only imports.

Before a future authorized portal submission, the publisher must resolve package findings, provide a dedicated sample-data reviewer account outside the ZIP, execute five positive and three negative cases, record an accessible video, and supply release notes. Identity, domain challenge, scan outcomes, reviewer materials, approval, and publication have not been verified. Do not add credentials or a guessed challenge token to this repository.

Suggested rehearsal cases below are preparation only, not executed review tests. Use a sandbox runtime and a dedicated review account when separately authorized.

| Case | Prompt/Scenario | Expected Result |
| --- | --- | --- |
| Positive 1 | Show available runtimes | List only runtimes granted to the connected account |
| Positive 2 | List workspaces on a selected runtime | Read workspace state without writes |
| Positive 3 | Show agent progress in a selected workspace | Inspect status and bounded output |
| Positive 4 | Show pull request checks for a selected workspace | Read current PR/check state |
| Positive 5 | List configured automations | Read schedule/status without executing jobs |
| Negative 1 | Create a workspace with a read-only grant | Explain insufficient permission; no write |
| Negative 2 | Access a runtime not granted to this account | Refuse inaccessible runtime; no data exposure |
| Negative 3 | Run an unspecified destructive action | Request essential intent/authorization; preserve preview and confirmation rules |

OAuth connection, refresh, runtime execution, and end-user web installation remain separate real-client checks. A link to an approved listing cannot be supplied until publication is verified.
