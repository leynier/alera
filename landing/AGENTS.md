# AGENTS

## Scope

This file applies to the `landing/` directory only.

The landing page is an Astro static site built with TypeScript, Tailwind CSS, Bun, and Vercel Analytics. These rules extend the repository-level `../AGENTS.md` for landing work.

This document defines governance only. It does not change runtime APIs, schemas, generated output, or package dependencies.

## Project Shape

- The site MUST remain an Astro static output project unless the user explicitly requests otherwise.
- `astro.config.mjs` MUST keep `output: 'static'` and the canonical site URL `https://alera.build`.
- Use the existing landing structure before adding new patterns:
  - `src/pages/index.astro` for page composition.
  - `src/layouts/Layout.astro` for document metadata, global imports, fonts, analytics, and page shell.
  - `src/components/*.astro` for page sections and reusable UI.
  - `src/styles/global.css` for global Tailwind layers, CSS variables, and shared utilities.
  - `tailwind.config.mjs` for theme tokens and Tailwind extensions.
  - `public/` for static assets referenced with root-relative paths.
- Do not edit `dist/`, `.astro/`, `node_modules/`, or other generated output as source.

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

- Landing UI values SHOULD come from `tailwind.config.mjs` and `src/styles/global.css` before adding ad-hoc literals.
- Keep the landing aligned with the app design direction: dark mode, grayscale-first palette, neutral accent emphasis, Inter for general text, and JetBrains Mono for terminal/code-adjacent text.
- Visible UI copy (headings, labels, CTAs, tooltips, alt text, and messages) MUST use sentence case.
- New colors, spacing, radii, type sizes, animation durations, and shared effects SHOULD be added as Tailwind theme values or CSS variables before repeated use.
- Existing token names and roles SHOULD remain consistent with the app baseline where practical: `bg`, `surface`, `surface-variant`, `surface-elevated`, `border`, `border-subtle`, `accent`, `on-accent`, `foreground`, `foreground-muted`, `foreground-faint`, `success`, `error`, `on-error`, and `warning`.
- Do not introduce a second visual system, icon style, font stack, or unrelated palette for the landing page.

## Astro and Tailwind Rules

- Prefer Astro components for static landing sections.
- Keep page-level composition in `src/pages/index.astro`; keep section markup in focused components under `src/components/`.
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

- For landing changes, run `bun run build` from `landing/`.
- If visual layout changes are made, also run or manually inspect a local preview with `bun run dev` or `bun run preview`.
- Do not commit build artifacts from `dist/` unless the user explicitly requests generated deployment output.
