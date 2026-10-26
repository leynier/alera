import { readFile } from "node:fs/promises";
import { dirname } from "node:path";

// Pi's own frontmatter split, kept here because the package that exports it
// was renamed between Pi releases.
export function stripFrontmatter(content) {
  const normalized = content.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  if (!normalized.startsWith("---")) return normalized;
  const end = normalized.indexOf("\n---", 3);
  if (end === -1) return normalized;
  return normalized.slice(end + 4).trim();
}

// Pi expands only one leading `/skill:name` command, so every `$name` mention
// of one of its skills appends that skill's instructions to the prompt, as
// T3 Code's injected extension does. The typed text stays unchanged.
export function registerSkillMentions(pi) {
  pi.on("input", async (event, ctx) => {
    if (!event.text.includes("$") || typeof pi.getCommands !== "function") return;
    const commands = pi.getCommands().filter((command) => command.source === "skill");
    const nativeSkill = /^\/skill:([^ ]+)(?: |$)/.exec(event.text)?.[1];
    const seen = new Set(nativeSkill === undefined ? [] : [nativeSkill]);
    const blocks = [];
    for (const match of event.text.matchAll(/(^|\s)\$([^\s]+)(?=\s|$)/g)) {
      const name = match[2];
      if (name === undefined || seen.has(name)) continue;
      const command = commands.find((candidate) => candidate.name === "skill:" + name);
      if (command === undefined) continue;
      seen.add(name);
      const path = command.sourceInfo?.path;
      try {
        const body = stripFrontmatter(await readFile(path, "utf8")).trim();
        blocks.push(
          `<skill name="${name}" location="${path}">\nReferences are relative to ${dirname(path)}.\n\n${body}\n</skill>`,
        );
      } catch {
        ctx.ui.notify(`Could not load skill ${name} from ${path}.`, "error");
      }
    }
    if (blocks.length === 0) return;
    return {
      action: "transform",
      text: event.text + "\n\n" + blocks.join("\n\n"),
      images: event.images,
    };
  });
}
