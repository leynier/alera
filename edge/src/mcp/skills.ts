import catalog from './skill_catalog.json';
import { isJsonObject, toolError, toolJson, type ToolResult } from './protocol';

/**
 * Skills written for MCP clients, sisters of the CLI skills agents use in
 * Alera terminals. They live only in this service, so they are answered here
 * without a runtime and match the tool catalog this edge serves.
 */
export const LIST_SKILLS_TOOL = 'list_skills';
export const READ_SKILL_TOOL = 'read_skill';

/** Appended to every other tool's description so a model reads the skills first. */
export const SKILLS_REMINDER =
  'Before using Alera tools for a task, read the matching Alera skill with list_skills and read_skill, unless you already did in this conversation.';

interface SkillFile {
  path: string;
  digest: string;
  text: string;
}

interface Skill {
  name: string;
  description: string;
  version: number;
  digest: string;
  files: SkillFile[];
}

export const SKILLS: readonly Skill[] = catalog.skills;

const READ_ONLY = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
};

export const SKILL_TOOL_DEFINITIONS = [
  {
    name: LIST_SKILLS_TOOL,
    title: 'List Skills',
    description:
      'List the Alera skills: guides that explain how to use the Alera tools for each kind of task, with their names, descriptions, versions, and files. Call it before the first Alera task of a conversation, then read the matching skill with read_skill. Needs no runtime.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    annotations: { title: 'List Skills', ...READ_ONLY },
  },
  {
    name: READ_SKILL_TOOL,
    title: 'Read Skill',
    description:
      "Read an Alera skill's SKILL.md, or one of the reference files it links to with file (such as references/workspaces.md). Follow it before calling other Alera tools for that task. Needs no runtime.",
    inputSchema: {
      type: 'object',
      properties: {
        name: {
          type: 'string',
          enum: SKILLS.map((skill) => skill.name),
          description: 'Skill name from list_skills.',
        },
        file: {
          type: 'string',
          description: 'File of the skill to read, as list_skills lists it (default SKILL.md).',
        },
      },
      required: ['name'],
      additionalProperties: false,
    },
    annotations: { title: 'Read Skill', ...READ_ONLY },
  },
];

export function isSkillTool(name: string): boolean {
  return name === LIST_SKILLS_TOOL || name === READ_SKILL_TOOL;
}

export function withSkillsReminder(description: string): string {
  return `${description} ${SKILLS_REMINDER}`;
}

function listSkills(): ToolResult {
  return toolJson({
    skills: SKILLS.map((skill) => ({
      name: skill.name,
      description: skill.description,
      version: skill.version,
      files: skill.files.map((file) => file.path),
    })),
  });
}

function readSkill(args: Record<string, unknown>): ToolResult {
  const unknown = Object.keys(args).filter((key) => key !== 'name' && key !== 'file');
  if (unknown.length > 0) return toolError(`invalid_argument: Unknown argument ${unknown[0]}.`);
  const skill = SKILLS.find((candidate) => candidate.name === args.name);
  if (!skill) {
    const names = SKILLS.map((candidate) => candidate.name).join(', ');
    return toolError(`not_found: No skill named ${String(args.name)}. Skills: ${names}.`);
  }
  if (args.file !== undefined && typeof args.file !== 'string') {
    return toolError('invalid_argument: file must be a string.');
  }
  const path = (args.file ?? 'SKILL.md').replace(/^\.\//, '');
  const file = skill.files.find((candidate) => candidate.path === path);
  if (!file) {
    const files = skill.files.map((candidate) => candidate.path).join(', ');
    return toolError(`not_found: ${skill.name} has no file ${path}. Files: ${files}.`);
  }
  return toolJson({
    name: skill.name,
    version: skill.version,
    file: file.path,
    digest: `sha256:${file.digest}`,
    text: file.text,
    files: skill.files.map((candidate) => candidate.path),
  });
}

/** Answers a skill tool call here, without a runtime. */
export function callSkillTool(name: string, args: unknown): ToolResult {
  const values = isJsonObject(args) ? args : {};
  return name === LIST_SKILLS_TOOL ? listSkills() : readSkill(values);
}
