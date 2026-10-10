import catalog from './tool_catalog.json';
import { isJsonObject } from './protocol';
import { isSkillTool, SKILL_TOOL_DEFINITIONS, withSkillsReminder } from './skills';

export type ToolAccess = 'read' | 'execute' | 'admin';

/** Catalog versions this edge understands. Version 2 adds the admin access class. */
const CATALOG_VERSIONS: readonly unknown[] = [1, 2];
const TOOL_ACCESS: readonly unknown[] = ['read', 'execute', 'admin'];

export interface CatalogTool {
  name: string;
  title: string;
  description: string;
  access: ToolAccess;
  timeoutSeconds: number;
  inputSchema: Record<string, unknown>;
  annotations: Record<string, unknown>;
}

export const LIST_RUNTIMES_TOOL = 'list_runtimes';

const RUNTIME_ARGUMENT = {
  type: 'string',
  description:
    'Runtime name or id from list_runtimes. Optional when exactly one granted runtime is online.',
};

function validCatalogTool(value: unknown): value is CatalogTool {
  return (
    isJsonObject(value) &&
    typeof value.name === 'string' &&
    value.name.length > 0 &&
    typeof value.title === 'string' &&
    typeof value.description === 'string' &&
    TOOL_ACCESS.includes(value.access) &&
    Number.isInteger(value.timeoutSeconds) &&
    (value.timeoutSeconds as number) > 0 &&
    isJsonObject(value.inputSchema) &&
    isJsonObject(value.annotations)
  );
}

export function loadCatalog(source: unknown): Map<string, CatalogTool> {
  if (!isJsonObject(source) || !CATALOG_VERSIONS.includes(source.version) || !Array.isArray(source.tools)) {
    throw new Error('Invalid MCP tool catalog');
  }
  const tools = new Map<string, CatalogTool>();
  for (const tool of source.tools) {
    if (!validCatalogTool(tool) || tool.name === LIST_RUNTIMES_TOOL || isSkillTool(tool.name) || tools.has(tool.name)) {
      throw new Error('Invalid MCP tool catalog entry');
    }
    tools.set(tool.name, tool);
  }
  return tools;
}

function bundledCatalog(): Map<string, CatalogTool> {
  try {
    return loadCatalog(catalog);
  } catch (error) {
    // A bad generated catalog must not take the relay and API proxy down with it.
    console.error('MCP tool catalog rejected', error);
    return new Map();
  }
}

export const RUNTIME_TOOLS = bundledCatalog();

function withRuntimeArgument(schema: Record<string, unknown>): Record<string, unknown> {
  const properties = isJsonObject(schema.properties) ? schema.properties : {};
  return { ...schema, type: 'object', properties: { ...properties, runtime: RUNTIME_ARGUMENT } };
}

const LIST_RUNTIMES_DEFINITION = {
  name: LIST_RUNTIMES_TOOL,
  title: 'List Runtimes',
  description: withSkillsReminder(
    'List the Alera runtimes this connection may use, with their names, ids, online state, and MCP access level.',
  ),
  inputSchema: { type: 'object', properties: {}, additionalProperties: false },
  annotations: {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  },
};

export function listedTools(tools: Map<string, CatalogTool> = RUNTIME_TOOLS): Array<Record<string, unknown>> {
  return [
    LIST_RUNTIMES_DEFINITION,
    ...SKILL_TOOL_DEFINITIONS,
    ...Array.from(tools.values(), (tool) => ({
      name: tool.name,
      title: tool.title,
      description: withSkillsReminder(tool.description),
      inputSchema: withRuntimeArgument(tool.inputSchema),
      annotations: tool.annotations,
    })),
  ];
}
