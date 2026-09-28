// Plain `tsc` does not know `.astro` modules; Astro's own tooling types them
// in `.astro` files. This lets TypeScript modules import components.
declare module '*.astro' {
  const Component: (props: Record<string, unknown>) => unknown;
  export default Component;
}
