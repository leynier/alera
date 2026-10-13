import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { URL as NodeURL } from 'node:url';
import { RUNTIME_TOOLS } from '../src/mcp/tools';
import { LIST_SKILLS_TOOL, READ_SKILL_TOOL, SKILLS, SKILLS_REMINDER } from '../src/mcp/skills';
import { buildSkillCatalog, serializeSkillCatalog, SKILL_CATALOG_PATH } from '../tool/skill_catalog';
import { mcpHarness } from './mcp_fixture';

const EDGE_TOOLS = ['list_runtimes', LIST_SKILLS_TOOL, READ_SKILL_TOOL];
// Chat tools belong to the injected credential-bound server, not the edge.
const CHAT_TOOL_SOURCE = readFileSync(
  new NodeURL('../../rust/alera-cli/src/mcp_tools/catalog/chat_orchestration.rs', import.meta.url),
  'utf8',
);
const CHAT_TOOLS = [...CHAT_TOOL_SOURCE.matchAll(/\b(?:read|execute|admin)\(\s*"(chat_[a-z_]+)"/g)].map((match) => match[1]);
// Snake case error codes and enum values in the skills, not tools.
const NON_TOOL_TERMS = new Set([
  'not_found',
  'invalid_argument',
  'capability_missing',
  'provider_unavailable',
  'timeout_pending',
  'runtime_unavailable',
  'runtime_offline',
  'insufficient_scope',
  'needs_input',
  'settled_only',
]);

const allTexts = SKILLS.flatMap((skill) => skill.files.map((file) => ({ skill, file })));

describe('MCP skill catalog', () => {
  test('the generated catalog matches the skill sources', () => {
    // Regenerate with `bun tool/skill_catalog.ts`.
    expect(readFileSync(SKILL_CATALOG_PATH, 'utf8')).toBe(serializeSkillCatalog(buildSkillCatalog()));
  });

  test('every Alera tool is explained by some skill', () => {
    const mentioned = new Set(allTexts.flatMap(({ file }) => [...file.text.matchAll(/`([a-z0-9_]+)`/g)].map((m) => m[1])));
    const missing = [...RUNTIME_TOOLS.keys(), ...CHAT_TOOLS, 'list_runtimes'].filter((name) => !mentioned.has(name));
    expect(missing).toEqual([]);
  });

  test('skills name only tools that exist', () => {
    const known = new Set([...RUNTIME_TOOLS.keys(), ...CHAT_TOOLS, ...EDGE_TOOLS]);
    const unknown = allTexts.flatMap(({ skill, file }) =>
      [...file.text.matchAll(/`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)`/g)]
        .map((match) => match[1])
        .filter((word) => !known.has(word) && !NON_TOOL_TERMS.has(word))
        .map((word) => `${skill.name}/${file.path}: ${word}`),
    );
    expect(unknown).toEqual([]);
  });

  test('chat-bound tools stay out of the public runtime catalog', () => {
    expect(CHAT_TOOLS.length).toBeGreaterThan(0);
    expect(new Set(CHAT_TOOLS).size).toBe(CHAT_TOOLS.length);
    expect([...RUNTIME_TOOLS.keys()].filter((name) => name.startsWith('chat_'))).toEqual([]);
  });

  test('links and skill names resolve', () => {
    const names = new Set(SKILLS.map((skill) => skill.name));
    const broken = allTexts.flatMap(({ skill, file }) => {
      const paths = new Set(skill.files.map((candidate) => candidate.path));
      const folder = file.path.includes('/') ? file.path.slice(0, file.path.lastIndexOf('/') + 1) : '';
      const links = [...file.text.matchAll(/\]\(([^)]+)\)/g)]
        .map((match) => match[1])
        .filter((target) => !paths.has(`${folder}${target}`))
        .map((target) => `${skill.name}/${file.path}: link ${target}`);
      const skills = [...file.text.matchAll(/`(alera-mcp[a-z-]*)`/g)]
        .map((match) => match[1])
        .filter((name) => !names.has(name))
        .map((name) => `${skill.name}/${file.path}: skill ${name}`);
      return [...links, ...skills];
    });
    expect(broken).toEqual([]);
  });

  test('a skill without frontmatter or with a mismatched name is rejected', () => {
    const { mkdtempSync, mkdirSync, writeFileSync } = require('node:fs');
    const { join } = require('node:path');
    const root = mkdtempSync(join(require('node:os').tmpdir(), 'skills-'));
    mkdirSync(join(root, 'good-name'));
    writeFileSync(join(root, 'good-name', 'SKILL.md'), '---\nname: other\ndescription: x\nmetadata:\n  version: 1\n---\n');
    expect(() => buildSkillCatalog(root)).toThrow('name must match its folder');
    writeFileSync(join(root, 'good-name', 'SKILL.md'), '# No frontmatter\n');
    expect(() => buildSkillCatalog(root)).toThrow('frontmatter');
    writeFileSync(join(root, 'good-name', 'SKILL.md'), '---\nname: good-name\ndescription: x\n---\n');
    expect(() => buildSkillCatalog(root)).toThrow('metadata.version');
  });
});

describe('MCP skill tools', () => {
  test('initialize tells the client to read the skills first', async () => {
    const harness = await mcpHarness();
    const { result } = await harness.rpc('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'test', version: '1' },
    });
    expect(result.instructions).toContain('list_skills');
    expect(result.instructions).toContain('read_skill');
  });

  test('every other tool reminds the model to read the skills', async () => {
    const harness = await mcpHarness();
    const { result } = await harness.rpc('tools/list');
    const names = result.tools.map((tool: { name: string }) => tool.name);
    expect(names.slice(0, 3)).toEqual(EDGE_TOOLS);
    for (const tool of result.tools) {
      if (tool.name === LIST_SKILLS_TOOL || tool.name === READ_SKILL_TOOL) {
        expect(tool.description).not.toContain(SKILLS_REMINDER);
        expect(tool.inputSchema.properties.runtime).toBeUndefined();
        expect(tool.annotations.readOnlyHint).toBe(true);
      } else {
        expect(tool.description.endsWith(` ${SKILLS_REMINDER}`)).toBe(true);
      }
    }
  });

  test('list_skills answers without reaching a runtime', async () => {
    const harness = await mcpHarness();
    const { result } = await harness.rpc('tools/call', { name: LIST_SKILLS_TOOL, arguments: {} });
    expect(result.isError).toBeUndefined();
    const listed = result.structuredContent.skills;
    expect(listed.map((skill: { name: string }) => skill.name)).toEqual(SKILLS.map((skill) => skill.name));
    expect(listed[0].files[0]).toBe('SKILL.md');
    expect(harness.originRequests).toHaveLength(0);
    expect(harness.relayCalls).toHaveLength(0);
  });

  test('read_skill returns SKILL.md by default and a reference by file', async () => {
    const harness = await mcpHarness();
    const entry = await harness.rpc('tools/call', { name: READ_SKILL_TOOL, arguments: { name: 'alera-mcp' } });
    expect(entry.result.structuredContent.file).toBe('SKILL.md');
    expect(entry.result.structuredContent.text).toContain('name: alera-mcp');
    expect(entry.result.structuredContent.digest).toMatch(/^sha256:[0-9a-f]{64}$/);
    const reference = await harness.rpc('tools/call', {
      name: READ_SKILL_TOOL,
      arguments: { name: 'alera-mcp', file: 'references/workspaces.md' },
    });
    expect(reference.result.structuredContent.text).toContain('# Projects And Workspaces');
    expect(harness.originRequests).toHaveLength(0);
  });

  test('read_skill refuses unknown skills, files, and arguments', async () => {
    const harness = await mcpHarness();
    const call = async (args: Record<string, unknown>) =>
      (await harness.rpc('tools/call', { name: READ_SKILL_TOOL, arguments: args })).result;
    const missingSkill = await call({ name: 'nope' });
    expect(missingSkill.isError).toBe(true);
    expect(missingSkill.content[0].text).toStartWith('not_found:');
    const escape = await call({ name: 'alera-mcp', file: '../alera-mcp-automations/SKILL.md' });
    expect(escape.content[0].text).toStartWith('not_found:');
    const extra = await call({ name: 'alera-mcp', runtime: 'laptop' });
    expect(extra.content[0].text).toStartWith('invalid_argument:');
  });
});
