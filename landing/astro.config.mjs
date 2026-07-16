import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://alera.build',
  output: 'static',
  vite: {
    plugins: [tailwindcss()],
  },
});
