// Builds src/mcp/skill_catalog.json from the skills in edge/skills.
// Run `bun tool/skill_catalog.ts` after editing a skill; a test fails while
// the generated copy is stale.

import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath, URL as NodeURL } from 'node:url';

const toolDirectory = fileURLToPath(new NodeURL('.', import.meta.url));
export const SKILLS_DIRECTORY = join(toolDirectory, '..', 'skills');
export const SKILL_CATALOG_PATH = join(toolDirectory, '..', 'src', 'mcp', 'skill_catalog.json');

const NAME = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const FILE = /^(SKILL\.md|references\/[a-z0-9-]+\.md)$/;
const MAX_FILE_BYTES = 64 * 1024;

export interface SkillFile {
  path: string;
  digest: string;
  text: string;
}

export interface Skill {
  name: string;
  description: string;
  version: number;
  digest: string;
  files: SkillFile[];
}

export interface SkillCatalog {
  version: 1;
  skills: Skill[];
}

function sha256(text: string): string {
  return createHash('sha256').update(text).digest('hex');
}

function filesUnder(directory: string): string[] {
  return readdirSync(directory)
    .sort()
    .flatMap((entry) => {
      const path = join(directory, entry);
      return statSync(path).isDirectory() ? filesUnder(path) : [path];
    });
}

/** Reads `name`, `description`, and `metadata.version` from the frontmatter. */
function frontmatter(text: string, where: string): { name: string; description: string; version: number } {
  const match = /^---\n([\s\S]*?)\n---\n/.exec(text);
  if (!match) throw new Error(`${where}: SKILL.md must start with frontmatter`);
  const fields = new Map<string, string>();
  let section = '';
  for (const line of match[1].split('\n')) {
    const field = /^(\s*)([A-Za-z-]+):\s*(.*)$/.exec(line);
    if (!field) throw new Error(`${where}: unsupported frontmatter line: ${line}`);
    const [, indent, key, value] = field;
    if (!indent) section = value ? '' : key;
    fields.set(indent ? `${section}.${key}` : key, value.trim());
  }
  const name = fields.get('name') ?? '';
  const description = fields.get('description') ?? '';
  const version = Number(fields.get('metadata.version'));
  if (!NAME.test(name) || name.length > 64) throw new Error(`${where}: invalid name ${name}`);
  if (!description || description.length > 1024) {
    throw new Error(`${where}: description must have 1 to 1024 characters`);
  }
  if (!Number.isInteger(version) || version < 1) throw new Error(`${where}: metadata.version must be a positive integer`);
  return { name, description, version };
}

export function buildSkillCatalog(directory: string = SKILLS_DIRECTORY): SkillCatalog {
  const skills = readdirSync(directory)
    .sort()
    .filter((entry) => statSync(join(directory, entry)).isDirectory())
    .map((folder): Skill => {
      const root = join(directory, folder);
      const files = filesUnder(root).map((path): SkillFile => {
        const relativePath = relative(root, path).split(sep).join('/');
        if (!FILE.test(relativePath)) throw new Error(`${folder}: unexpected file ${relativePath}`);
        const text = readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
        if (Buffer.byteLength(text) > MAX_FILE_BYTES) throw new Error(`${folder}: ${relativePath} is too large`);
        return { path: relativePath, digest: sha256(text), text };
      });
      // SKILL.md first, references after it in name order.
      files.sort((a, b) => (a.path === 'SKILL.md' ? -1 : b.path === 'SKILL.md' ? 1 : a.path.localeCompare(b.path)));
      const entry = files[0];
      if (entry?.path !== 'SKILL.md') throw new Error(`${folder}: SKILL.md is missing`);
      const { name, description, version } = frontmatter(entry.text, folder);
      if (name !== folder) throw new Error(`${folder}: name must match its folder`);
      const digest = sha256(files.map((file) => `${file.path}\0${file.text}`).join('\0'));
      return { name, description, version, digest, files };
    });
  return { version: 1, skills };
}

export function serializeSkillCatalog(catalog: SkillCatalog): string {
  return `${JSON.stringify(catalog, null, 2)}\n`;
}

if (import.meta.main) {
  writeFileSync(SKILL_CATALOG_PATH, serializeSkillCatalog(buildSkillCatalog()));
}
