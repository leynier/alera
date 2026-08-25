import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import starlight from '@astrojs/starlight';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://alera.build',
  output: 'static',
  build: {
    inlineStylesheets: 'always',
  },
  integrations: [
    starlight({
      title: 'Alera',
      description:
        'Learn how to run CLI coding agents in Alera: projects, worktrees, orchestration, mobile pairing, and quotas.',
      favicon: '/favicon.svg',
      logo: {
        src: './src/assets/logo.png',
        alt: 'Alera',
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/leynier/alera',
        },
      ],
      editLink: {
        baseUrl: 'https://github.com/leynier/alera/edit/main/landing/',
      },
      customCss: ['./src/styles/docs.css'],
      components: {
        Head: './src/components/docs/Head.astro',
        SocialIcons: './src/components/docs/SocialIcons.astro',
        ThemeProvider: './src/components/docs/ThemeProvider.astro',
        ThemeSelect: './src/components/docs/ThemeSelect.astro',
      },
      expressiveCode: {
        themes: ['github-dark'],
        useStarlightDarkModeSwitch: false,
        useStarlightUiThemeColors: false,
        styleOverrides: {
          borderRadius: '10px',
          borderWidth: '1px',
          borderColor: '#323232',
          codeBackground: '#181818',
        },
      },
      sidebar: [
        {
          label: 'Start',
          items: [
            { label: 'Get Started', slug: 'docs' },
            { label: 'Install', slug: 'docs/install' },
          ],
        },
        {
          label: 'Workbench',
          items: [
            { label: 'Projects And Workspaces', slug: 'docs/projects' },
            { label: 'CLI Agents', slug: 'docs/agents' },
            { label: 'Worktrees', slug: 'docs/worktrees' },
            { label: 'Alera.toml', slug: 'docs/alera-toml' },
          ],
        },
        {
          label: 'Coordinate',
          items: [{ label: 'Orchestration', slug: 'docs/orchestration' }],
        },
        {
          label: 'Stay In The Loop',
          items: [
            { label: 'Mobile Pairing', slug: 'docs/mobile' },
            { label: 'Quotas And Resources', slug: 'docs/quotas' },
          ],
        },
      ],
    }),
    sitemap(),
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
