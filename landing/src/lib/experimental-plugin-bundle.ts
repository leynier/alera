import { strToU8 } from 'fflate';
import { buildAgentPluginBundle } from './agent-plugin-bundle';
import { validateAgentPluginManifest, validateAgentPluginMcp } from './agent-plugin-validation';
import { buildClaudePluginBundle } from './claude-plugin-bundle';
import { buildCursorPluginBundle } from './cursor-plugin-bundle';
import { buildPluginArchive } from './plugin-archive';
import { buildPluginBundle } from './plugin-bundle';

export const EXPERIMENTAL_PLUGIN_ARCHIVE = 'alera-combined-experimental.zip';
export const EXPERIMENTAL_PLUGIN_NAME = 'alera-experimental';

/** Explicit opt-in only: never called by static website or CI artifact publishing. */
export function buildExperimentalPluginBundle(root: string) {
  const core = buildAgentPluginBundle(root);
  const openai = buildPluginBundle(root);
  const claude = buildClaudePluginBundle(root);
  const cursor = buildCursorPluginBundle(root);
  const files = { ...core.files };
  const json = (path: string, value: unknown) => { files[path] = strToU8(`${JSON.stringify(value, null, 2)}\n`); };
  const parse = (bytes: Uint8Array) => JSON.parse(new TextDecoder().decode(bytes));
  const title = 'Alera Experimental';
  const manifest = { ...parse(core.files['plugin.json']!), name: EXPERIMENTAL_PLUGIN_NAME, description: 'Experimental combined Alera plugin. Client compatibility is not verified.' };
  const openaiExtensions = parse(openai.files['plugin.json']!).extensions;
  openaiExtensions['com.openai'].interface.displayName = title;
  openaiExtensions['com.openai'].interface.shortDescription = 'Experimental Alera Bundle';
  json('plugin.json', { ...manifest, extensions: openaiExtensions });
  json('.codex-plugin/plugin.json', { ...parse(openai.files['.codex-plugin/plugin.json']!), name: EXPERIMENTAL_PLUGIN_NAME, description: manifest.description, interface: openaiExtensions['com.openai'].interface });
  json('.claude-plugin/plugin.json', { ...parse(claude.files['.claude-plugin/plugin.json']!), name: EXPERIMENTAL_PLUGIN_NAME, displayName: title, description: manifest.description });
  json('.cursor-plugin/plugin.json', { ...parse(cursor.files['.cursor-plugin/plugin.json']!), name: EXPERIMENTAL_PLUGIN_NAME, description: manifest.description });
  files['.mcp.json'] = claude.files['.mcp.json']!;
  files['assets/logo.png'] = openai.files['assets/logo.png']!;
  files['assets/logo-dark.png'] = openai.files['assets/logo-dark.png']!;
  files['README.md'] = strToU8(`# Alera Experimental Combined Plugin\n\nOne preliminary example, version 1.0.0. Experimental only. Keep the five separate distributions for normal use. This ZIP has one plugin folder, one shared set of five portable skills and references, and competing client manifests. It contains no credentials, hooks, installer, or local MCP executable. Do not install it over an existing Alera plugin.\n\n## Layout And Limits\n\n- Agent Plugins core and GitHub Copilot: root plugin.json and mcp.json (1.0.0, streamable-http). The root includes com.openai presentation metadata as a standard namespaced extension; this combined example is not the pure Agent Plugin distribution. Copilot needs no extension components for skills and MCP. Its official loader prioritizes the standard root manifest over legacy alternatives. No Copilot logo field is invented.\n- ChatGPT/Codex: root com.openai metadata plus .codex-plugin/plugin.json and bundled Alera images. Native .mcp.json is shared with Claude and has no OpenAI OAuth declaration; actual ChatGPT web authorization and which manifest takes priority are not verified. This is a deliberate compatibility boundary, not a production replacement.\n- Claude web: .claude-plugin/plugin.json, shared skills, and .mcp.json with type http and the fixed URL. Claude Code validation is only format evidence; extra manifests, web upload acceptance, connector installation, and OAuth must be checked in Claude web. Do not infer web support from CLI acceptance.\n- GrokBot Cursor: .cursor-plugin/plugin.json and shared skills. Native Cursor discovery competes with the root Agent Plugin manifest and standard mcp.json. The documentation describes both formats without specifying a universal precedence for their co-location. Grok Bot's guide only documents connecting available plugins, not arbitrary ZIP import or native Cursor-folder synchronization.\n- Other clients: require explicit Agent Plugins 1.0 support. The compatible-client catalog lists Kiro, but Kiro-specific installation or behavior is not implemented or tested. Google and Gemini are excluded.\n\n## Preliminary Test\n\nVerify the adjacent SHA-256 checksum, extract the alera-experimental folder without losing hidden directories, and inspect the README before using a client's documented local or upload flow. Confirm the discovered identity, five skills, selected MCP configuration, and any ignored or rejected extra files. Stop on an unsupported format or missing tools. Review actual consent and runtime access separately; this package does not pin scopes or change grants. Use only list_runtimes and list_projects as connectivity checks after authorization. No real installation, OAuth exchange, refresh, or runtime access is established by package validators.\n\n## Sources\n\n[Agent Plugins](https://agent-plugins.org/specification), [Copilot manifest precedence](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference), [Cursor formats](https://cursor.com/docs/reference/plugins), [Grok Bot connections](https://cursor.com/help/grok-bot/connect-plugins), [Claude web](https://claude.com/docs/plugins/build), and [OpenAI plugin format](https://developers.openai.com/plugins/build/plugins).\n`);
  if (!validateAgentPluginManifest(parse(files['plugin.json']!)) || !validateAgentPluginMcp(parse(files['mcp.json']!))) throw new Error('Experimental portable core fails official schemas');
  return buildPluginArchive(files, EXPERIMENTAL_PLUGIN_NAME, EXPERIMENTAL_PLUGIN_ARCHIVE);
}
