/**
 * The documentation index, grouped and in reading order. The sidebar, the
 * mobile menu, the previous/next pager and the section eyebrow all read this
 * one list, so they cannot disagree. Adding a page means adding a line here
 * and an `.mdx` file under `src/content/docs/`; the docs route refuses to
 * build when the two drift apart.
 */
export interface DocLink {
  id: string;
  label: string;
}

export interface DocSection {
  title: string;
  pages: readonly DocLink[];
}

export const DOC_SECTIONS: readonly DocSection[] = [
  {
    title: 'Start',
    pages: [
      { id: 'index', label: 'Get Started' },
      { id: 'install', label: 'Install' },
    ],
  },
  {
    title: 'Workbench',
    pages: [
      { id: 'projects', label: 'Projects And Workspaces' },
      { id: 'new-workspace', label: 'New Workspace' },
      { id: 'worktrees', label: 'Worktrees' },
      { id: 'alera-toml', label: 'alera.toml' },
      { id: 'terminals', label: 'Terminals And Panes' },
      { id: 'files-and-search', label: 'Files, Search, And Previews' },
      { id: 'keyboard-shortcuts', label: 'Keyboard Shortcuts' },
    ],
  },
  {
    title: 'Agents',
    pages: [
      { id: 'agents', label: 'CLI Agents' },
      { id: 'agent-profiles', label: 'Agent Profiles' },
      { id: 'agent-states', label: 'Agent States And Attention' },
      { id: 'ai-assist', label: 'AI Assist And Dictation' },
    ],
  },
  {
    title: 'Review',
    pages: [
      { id: 'source-control', label: 'Source Control' },
      { id: 'pull-requests', label: 'Pull Requests And Checks' },
    ],
  },
  {
    title: 'Coordinate',
    pages: [
      { id: 'orchestration', label: 'Orchestration' },
      { id: 'run-board', label: 'Run Board And Workflows' },
      { id: 'automations', label: 'Automations' },
    ],
  },
  {
    title: 'Remote And Mobile',
    pages: [
      { id: 'mobile', label: 'Mobile Companion' },
      { id: 'remote-access', label: 'Remote Access' },
      { id: 'remote-hosts', label: 'Remote Hosts' },
      { id: 'accounts', label: 'Accounts, Push, And Sync' },
    ],
  },
  {
    title: 'Operate',
    pages: [
      { id: 'quotas', label: 'Quotas And Resources' },
      { id: 'cli', label: 'Alera CLI' },
      { id: 'troubleshooting', label: 'Troubleshooting' },
    ],
  },
];

/** Every page in reading order, for previous/next. */
export const DOC_PAGES: readonly DocLink[] = DOC_SECTIONS.flatMap((section) => section.pages);

export function docHref(id: string): string {
  return id === 'index' ? '/docs' : `/docs/${id}`;
}

export function docLabel(id: string): string | undefined {
  return DOC_PAGES.find((page) => page.id === id)?.label;
}

/** The group a page belongs to, shown as the eyebrow above its title. */
export function docSectionTitle(id: string): string | undefined {
  return DOC_SECTIONS.find((section) => section.pages.some((page) => page.id === id))?.title;
}

export function adjacentDocs(id: string): { previous?: DocLink; next?: DocLink } {
  const index = DOC_PAGES.findIndex((page) => page.id === id);
  if (index < 0) return {};
  return { previous: DOC_PAGES[index - 1], next: DOC_PAGES[index + 1] };
}

/**
 * Names every id that is in one place but not the other, so a missing page or
 * a forgotten nav entry fails the build with a readable message.
 */
export function navigationDrift(entryIds: readonly string[]): string[] {
  const listed = new Set(DOC_PAGES.map((page) => page.id));
  const present = new Set(entryIds);
  const problems: string[] = [];
  for (const id of listed) {
    if (!present.has(id)) problems.push(`"${id}" is in DOC_SECTIONS but has no src/content/docs/${id}.mdx`);
  }
  for (const id of present) {
    if (!listed.has(id)) problems.push(`src/content/docs/${id}.mdx is not listed in DOC_SECTIONS`);
  }
  return problems;
}
