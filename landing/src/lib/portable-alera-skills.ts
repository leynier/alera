import { join } from 'node:path';
import { strToU8 } from 'fflate';
import { buildSkillCatalog } from '../../../edge/tool/skill_catalog';

const remoteReferenceInstruction = 'Read only the references the task needs. Read them with `read_skill`, passing the reference path as `file`.';
const portableReferenceInstruction = 'Read only the bundled references the task needs through the client\'s file-reading facilities, resolving relative links inside this skill folder. If a bundled file cannot be read and the remote `read_skill` tool is exposed, pass this skill name and the reference path as `file`; report that the remote copy may differ from the installed package version.';

export function adaptPortableAleraSkill(text: string, entrypoint: boolean): string {
  if (!entrypoint) return text;
  const adapted = text.replace(remoteReferenceInstruction, portableReferenceInstruction).replace('  version: 1\n', '  version: "1"\n');
  return `${adapted.trimEnd()}\n\n## Connection And Client Capabilities\n\nUse the remote Alera MCP connection only after its tools are actually available. If they are missing, load the bundled alera-setup skill and explain the client's documented installation or authorization requirements. Do not assume a native subagent, shell, local MCP process, or shared account synchronization. The agents and coordinator terminals described here run on the selected Alera runtime. Credentials belong in the client's authorization flow, never in chat or package files. Do not bypass scope failures or upgrade permissions to test connectivity.\n`;
}

export function portableAleraSkillFiles(landingRoot: string) {
  const files: Record<string, Uint8Array> = {};
  for (const skill of buildSkillCatalog(join(landingRoot, '..', 'edge', 'skills')).skills) {
    for (const file of skill.files) files[`skills/${skill.name}/${file.path}`] = strToU8(adaptPortableAleraSkill(file.text, file.path === 'SKILL.md'));
  }
  return files;
}
