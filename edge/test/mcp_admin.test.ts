import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { MCP_SCOPES } from '../src/mcp/protocol';
import { loadCatalog, RUNTIME_TOOLS, type CatalogTool } from '../src/mcp/tools';
import { accessToken, mcpHarness } from './mcp_fixture';

const ADMIN_TOOL: CatalogTool = {
  name: 'test_admin_tool',
  title: 'Test Admin Tool',
  description: 'An administrative tool used only by these tests.',
  access: 'admin',
  timeoutSeconds: 30,
  inputSchema: { type: 'object', properties: {}, additionalProperties: false },
  annotations: { readOnlyHint: false, destructiveHint: true },
};

describe('MCP admin access', () => {
  beforeAll(() => {
    RUNTIME_TOOLS.set(ADMIN_TOOL.name, ADMIN_TOOL);
  });

  afterAll(() => {
    RUNTIME_TOOLS.delete(ADMIN_TOOL.name);
  });

  test('the challenge advertises the admin scope', () => {
    expect(MCP_SCOPES).toBe('mcp:read mcp:execute mcp:admin');
  });

  test('catalog version 2 with admin tools loads and unknown classes are rejected', () => {
    const tools = loadCatalog({ version: 2, tools: [ADMIN_TOOL] });
    expect(tools.get(ADMIN_TOOL.name)?.access).toBe('admin');
    expect(loadCatalog({ version: 1, tools: [] }).size).toBe(0);
    expect(() => loadCatalog({ version: 2, tools: [{ ...ADMIN_TOOL, access: 'owner' }] })).toThrow();
  });

  test('an admin tool without mcp:admin is a tool error that names the scope', async () => {
    const harness = await mcpHarness();
    for (const scope of ['mcp:read', 'mcp:read mcp:execute']) {
      const token = await accessToken(harness.privateKey, { scope });
      const { result } = await harness.rpc('tools/call', { name: ADMIN_TOOL.name }, token);
      expect(result.isError).toBeTrue();
      expect(result.content[0].text).toBe(
        'insufficient_scope: test_admin_tool needs the mcp:admin scope, but this connection was not granted administrative tools. Reconnect Alera and allow administrative tools.',
      );
    }
    expect(harness.originRequests).toBeEmpty();
    expect(harness.relayCalls).toBeEmpty();
  });

  test('an admin tool with mcp:admin asks the gateway for an admin call and reaches the runtime', async () => {
    const harness = await mcpHarness();
    const token = await accessToken(harness.privateKey, { scope: 'mcp:read mcp:execute mcp:admin' });
    const { result } = await harness.rpc(
      'tools/call',
      { name: ADMIN_TOOL.name, arguments: { runtime: 'laptop' } },
      token,
    );
    expect(result.isError).toBeFalse();
    expect(harness.originBodies[0]).toEqual({ runtime: 'laptop', tool: ADMIN_TOOL.name, access: 'admin' });
    expect(harness.relayCalls.map(({ body }) => body.tool)).toEqual([ADMIN_TOOL.name]);
  });
});
