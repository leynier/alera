# AGENTS

## Scope

This file applies to the `landing/` directory only.

The landing page is an Astro static site built with TypeScript, Tailwind CSS, Bun, and Vercel Analytics. These rules extend the repository-level `../AGENTS.md` for landing work.

This document defines governance only. It does not change runtime APIs, schemas, generated output, or package dependencies.

## Project Shape

- The site MUST remain an Astro static output project unless the user explicitly requests otherwise.
- `astro.config.mjs` MUST keep `output: 'static'` and the canonical site URL `https://alera.build`.
- Use the existing landing structure before adding new patterns:
  - `src/pages/*.astro` for page composition: `index.astro` is the marketing home, `download.astro` is the install page, and the trust documents live at `privacy.astro`, `terms.astro`, and `account/delete.astro`.
  - `src/pages/blog/index.astro` is the blog index, `src/pages/blog/tags/[tag].astro` is one page per tag in use, and `src/pages/blog/[id].astro` renders individual posts inside `src/layouts/BlogPostLayout.astro`, which shares the docs outline, heading links, and code frames and ends with the post's related docs and its newer and older neighbours.
  - `src/pages/rss.xml.ts` emits the blog RSS feed at `/rss.xml`.
  - `src/content.config.ts` defines the `blog` collection (Markdown or MDX posts under `src/content/blog/`, each with one to three `tags` from the closed vocabulary in `src/lib/blog-tags.ts`, an optional `featured` flag, and `relatedDocs` that must name existing docs ids) and the `docs` collection (flat MDX files under `src/content/docs/`), both with the `glob` loader and a Zod schema.
  - Product documentation is a custom docs system in the same Astro app, served at `/docs`, with no documentation framework: a framework would bring a second design system to either fight or rebuild. `src/content/docs/index.mdx` is `/docs` and every other file is `/docs/<id>`, rendered by `src/pages/docs/[...slug].astro` inside `src/layouts/DocsLayout.astro`.
  - `src/lib/docs-navigation.ts` (`DOC_SECTIONS`) is the single source of the docs order and grouping: the sidebar, the mobile menu, the pager, and the section eyebrow all read it. Adding a page means adding an entry there and an `.mdx` file; the docs route fails the build when the two drift apart, and `docs-navigation.test.ts` checks the same.
  - The page outline and heading self-links come from `src/lib/heading-outline.ts` over the rendered HTML, and code frames (language label plus copy button) from `src/lib/code-block-frame.ts`. Pages never write their own table of contents.
  - Docs search is Pagefind, indexed in `astro:build:done` by `config/docs-search-index.mjs` (docs pages only) and queried by `src/components/docs/DocsSearch.astro` in the site's own tokens. The build fails when the index is empty.
  - MDX components available to every docs page without an import are listed in `src/components/docs/mdx-components.ts` (`Callout`, `DocCard`, `DocCardGrid`, `DocLinkButton`, `ShortcutTable`, `Steps`). Prefer these over raw HTML in MDX.
  - Keyboard shortcuts on the site are printed by `src/lib/key-chord-label.ts`, a port of the app's `key_chord.dart`, and the Keyboard Shortcuts page lists `src/data/keyboard-shortcuts.ts`. Both have tests that read the app's sources: write a registry chord in its canonical form (`Mod+Shift+N`), never as a hand-typed platform glyph, and `keyboard-shortcuts.test.ts` fails when a docs page cites a `Mod+` chord the registry does not bind. Only keys the registry does not own, such as the terminal's copy and paste, are written per platform.
  - Fenced code on the docs and the blog uses the `alera-dark` Shiki theme in `config/alera-code-theme.mjs`, derived from the app's editor syntax colors. Do not add a light theme: the site is dark-only.
  - `src/components/Prose.astro` holds the long-form typography shared by the docs and the blog. Its element styles sit inside `:where()` so components rendered inside prose can override them.
  - These `/docs` pages are for people using Alera and describe shipped behavior only. Contributor internals stay in the repository `docs/` directory.
  - `src/pages/404.astro` is the site-wide not-found page.
  - Keep the explicit `sitemap()` integration so marketing, blog, and docs routes stay in the sitemap; it drops `/404` and `/signed-in` and writes URLs without a trailing slash to match canonicals. Shared `@font-face` rules live in `src/styles/fonts.css`.
  - `src/lib/blog.ts` holds shared blog helpers (`getPublishedBlogPosts`, date formatting, reading time from `src/lib/reading-time.ts`), and `src/lib/blog-listing.ts` the ordering rules (newest first, the featured lead post, tag counts, neighbours) with unit tests. Draft posts (`draft: true`) MUST be omitted from production builds and remain visible in local/dev builds.
  - A published post keeps its `pubDate` and URL for good. A correction adds `updatedDate` and a dated note at the top of the body (`> **Update, September 2026:** ...`) instead of rewriting the post; fix inline only what would mislead a reader who copies it, such as a broken command. `e2e/blog.spec.ts` lists every published URL.
  - `src/components/blog/` holds blog-specific presentational components (`BlogIndex`, `BlogPostCard`, `BlogTagBar`, `BlogTagChips`, `BlogPostHeader`, `RelatedDocs`, `BlogPager`). A new tag belongs in `BLOG_TAGS` with a line in `TAG_DESCRIPTIONS`, never in one post's front matter alone.
  - `src/data/install-channels.ts` is the single source of every install command, asset name, release URL, and Linux repository detail. The download page (`src/pages/download.astro` plus `src/components/download/`), the home Install section, and the docs read it; `test/unit/landing_release_links_test.dart` and `linux_install_script_test.dart` check it against the release workflow and the installer.
  - `plugin/` owns downloadable plugin metadata and onboarding. `src/data/plugin.ts` exposes its version, download URLs, and skill descriptions; `install-channels.ts` re-exports the plugin download. `config/plugin-download.ts` builds the static ZIP and checksum from `plugin/`, `../edge/skills/`, and the existing light/dark logos. Keep package sources available outside the landing root, preserve hidden compatibility and marketplace files, and bump the plugin version when any bundled source changes. See `../docs/plugin-bundle.md`.
  - The home page MUST keep an `#install` section (`src/components/Install.astro`): `public/install.sh` writes `https://alera.build/#install` into the package sources it creates.
  - `src/components/CommandBlock.astro` renders a copyable command with the same `[data-code-block]` / `[data-code-copy]` contract as docs code frames, so `src/scripts/code-block-copy.ts` is the only copy script. `src/components/BrandMark.astro` holds the GitHub, Flutter, and Rust marks (Lucide ships no logos); reuse it instead of pasting SVG paths.
  - Icons come from `@lucide/astro`, pinned to the Lucide release `lucide_icons_flutter` bundles in the app, imported per icon (`@lucide/astro/icons/<name>`) so only used icons ship.
  - `src/components/TrustDocument.astro` for legal and policy pages, which carry their own navigation instead of the marketing navbar.
  - `src/layouts/Layout.astro` for document metadata, global imports, fonts, analytics, and page shell. Blog posts MAY pass `ogType="article"` plus optional `publishedTime` / `modifiedTime`.
  - `src/components/*.astro` for page sections and reusable UI.
  - `src/styles/global.css` for the Tailwind `@theme` tokens, global layers, CSS variables, and shared `@utility` definitions (Tailwind CSS v4 has no `tailwind.config.mjs`; the plugin is registered in `astro.config.mjs` via `@tailwindcss/vite`).
  - `public/` for static assets referenced with root-relative paths.
  - The home Product section (`src/components/Product.astro`, `/#product`) is the interactive product demo in `src/components/demo/`, documented in `../docs/landing-demo.md`. It redraws the desktop and Android apps in HTML, CSS, and SVG from the app's own tokens, icons, agent marks, and copy; do not replace it with screenshots or a video.
  - The repository README media in `../assets/product/` (an animated WebP cut and one poster per chapter) are rendered from the demo by `bun run media:demo` after `bun run build`, never recorded from a screen. Say so wherever they appear, keep the note that agent sessions are staged samples, and do not overclaim live-device capture or real agent output. `src/data/demo/demo-media.test.ts` fails when the storyboard changes without a new render.
  - `@astrojs/sitemap` is registered in `astro.config.mjs` and MUST stay enabled while `site` is set.
- Do not edit `dist/`, `.astro/`, `node_modules/`, or other generated output as source.
- Prefer Astro Content Collections for blog posts. Do not add loose Markdown routes under `src/pages/blog/` or use removed APIs such as `Astro.glob()` / `entry.slug`.

## Product Demo

- Demo values MUST come from the app source they copy: colors, sizes, radii, and durations from `src/styles/demo/tokens.css` (a mirror of `AleraTokens`), icons through the roles in `src/components/demo/primitives/app-icons.ts` and `mobile-icons.ts`, agent marks and the logo as byte-for-byte copies, shortcuts from `src/data/demo/shortcuts.ts`, and every quoted string from `src/data/demo/app-copy.ts` with the file that ships it. `src/data/demo/fidelity.test.ts` checks all of these against the app; when it fails, fix the demo in the same change as the app.
- Demo CSS lives in `src/styles/demo/`, scoped under `[data-alera-demo]`, and uses the app's values rather than the landing `@theme` tokens. This is the one exception to the landing design system: the demo replicates Flutter widgets, and some landing tokens deliberately differ from the app (`foreground-faint` is lighter on the site for contrast).
- Agent sessions in the demo are staged samples. The note under the player says so and names the features shown that are opt-in in the app; keep it accurate when the story changes.
- The scene MUST stay deterministic: its state comes only from the storyboard (`src/data/demo/storyboard*.ts`) through the pure `frameAt(t, layout)` in `src/scripts/demo/timeline.ts`, and motion inside it is a paused CSS animation positioned by `--demo-t`. Do not add timers, free-running animations, or random values to the scene.
- Every node a storyboard key touches MUST carry a `data-demo-node` id in the scene; `src/data/demo/storyboard.test.ts` fails otherwise.
- Continuous motion animates only `transform` and `opacity`. The player MUST keep a visible Pause control, pause when scrolled away or when the tab is hidden, skip autoplay under reduced motion, and never loop. The stage stays `aria-hidden` and `inert`, with the captions and **Read The Demo As Text** carrying the story.
- `/?demo=capture` mounts the demo without playing and exposes `window.__aleraDemo.seek(t)` for rendering exact frames.

## Bun Usage

- Use Bun for landing dependency and script commands.
- Use `bun install` instead of `npm install`, `yarn install`, or `pnpm install`.
- Use `bun run dev` for local development.
- Use `bun run build` for production validation.
- Use `bun run preview` for local preview of the built site.
- Use `bun run <script>` instead of `npm run`, `yarn run`, or `pnpm run`.
- Use `bunx <package> <command>` instead of `npx <package> <command>`.
- Bun automatically loads `.env`; do not add `dotenv` for landing work.

## Landing Design System

- Landing UI values SHOULD come from the `@theme` tokens in `src/styles/global.css` before adding ad-hoc literals.
- Keep the landing aligned with the app design direction: dark mode, grayscale-first palette, neutral accent emphasis, Inter for general text, and JetBrains Mono for terminal/code-adjacent text.
- Visible UI copy (headings, labels, CTAs, tooltips, alt text, and messages) MUST use title case (e.g., "New Workspace", "AI Assist").
- New colors, spacing, radii, type sizes, animation durations, and shared effects SHOULD be added as Tailwind theme values or CSS variables before repeated use.
- Existing token names and roles SHOULD remain consistent with the app baseline where practical: `bg`, `surface`, `surface-variant`, `surface-elevated`, `border`, `border-subtle`, `accent`, `on-accent`, `foreground`, `foreground-muted`, `foreground-faint`, `success`, `error`, `on-error`, and `warning`.
- Do not introduce a second visual system, icon style, font stack, or unrelated palette for the landing page.

## Astro and Tailwind Rules

- Prefer Astro components for static landing sections.
- Keep page-level composition in `src/pages/`; keep section markup in focused components under `src/components/`.
- Pages MUST pass `canonicalPath` to `Layout.astro`, or they inherit the home page as their canonical URL.
- Links to home-page sections MUST be written as `/#section`, never as a bare `#section`, so they resolve from subpages.
- The SignPath attribution ("Free code signing provided by SignPath.io, certificate by SignPath Foundation") is required verbatim on the home page and the download page, and MUST stay one contiguous string rather than being split across markup.
- Use Tailwind utility classes and existing shared utilities from `src/styles/global.css` before writing one-off CSS.
- If a utility is reused across components, define it in `src/styles/global.css` rather than duplicating long class sequences or inline styles.
- Keep metadata, social tags, fonts, favicon links, and analytics wiring centralized in `src/layouts/Layout.astro`.
- Static assets MUST live in `public/` and SHOULD be referenced with root-relative paths such as `/logo.png`.
- Images and meaningful SVGs MUST include useful alt text or accessible labels. Decorative SVGs SHOULD be hidden from assistive technology.

## Responsive and Content Quality

- Landing changes MUST be checked at mobile and desktop widths.
- Pay particular attention to the hero, fixed navigation, CTA buttons, section cards, workflow steps, footer, and long marketing copy.
- Text MUST not overflow or overlap its container at common mobile widths.
- CTA states MUST not imply an action is available unless the linked/download behavior is implemented. If a control is intentionally unavailable, keep the current "coming soon" behavior or an equivalent explicit disabled/placeholder state.
- Marketing copy MUST not overclaim product behavior beyond what the app actually supports.

## Validation

- For landing changes, run `bun test` and `bun run build` from `landing/`, then `bunx playwright test` against the built site (`bun run check` runs all three). Locally, set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` to reuse an installed Chromium instead of downloading one.
- Unit tests (`*.test.ts`) live next to the code under `src/` and run with `bun test`; `bunfig.toml` keeps that runner out of `e2e/`. Playwright specs live in `e2e/`, and specs with `mobile` in their name run only at a 390 px viewport.
- If visual layout changes are made, also run or manually inspect a local preview with `bun run dev` or `bun run preview`.
- Do not commit build artifacts from `dist/` unless the user explicitly requests generated deployment output.
