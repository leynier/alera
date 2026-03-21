/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        surface: '#111114',
        'surface-container-lowest': '#0a0a0d',
        'surface-container-low': '#18181b',
        'surface-container': '#1f1f22',
        'surface-container-high': '#27272a',
        'surface-container-highest': '#333336',
        'surface-variant': '#333336',
        'surface-bright': '#3a3a3d',
        primary: '#e2e2e2',
        'primary-container': '#d0d0d0',
        brand: '#e2e2e2',
        secondary: '#c6c6c6',
        'secondary-container': '#27272a',
        'on-surface': '#e2e2e2',
        'on-surface-variant': '#a1a1a4',
        outline: '#71717a',
        'outline-variant': '#3f3f46',
        'on-primary': '#111114',
        'on-primary-fixed': '#ffffff',
        'on-secondary-fixed': '#e2e2e2',
        'nav-inactive': '#71717a',
        error: '#fca5a5',
        'on-error': '#450a0a',
      },
      borderRadius: {
        DEFAULT: '0.25rem',
        lg: '0.5rem',
        xl: '0.75rem',
        full: '9999px',
      },
      fontFamily: {
        body: ['Inter', 'system-ui', 'sans-serif'],
        headline: ['Space Grotesk', 'system-ui', 'sans-serif'],
        label: ['Space Grotesk', 'system-ui', 'sans-serif'],
        display: ['Space Grotesk', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
      fontSize: {
        'headline-lg': ['28px', { lineHeight: '1.2', letterSpacing: '-0.5px', fontWeight: '600' }],
        'headline-md': ['22px', { lineHeight: '1.3', letterSpacing: '-0.3px', fontWeight: '600' }],
        'headline-sm': ['18px', { lineHeight: '1.4', letterSpacing: '-0.2px', fontWeight: '600' }],
        'title-lg': ['16px', { lineHeight: '1.5', fontWeight: '600' }],
        'title-md': ['14px', { lineHeight: '1.5', fontWeight: '500' }],
        'body-lg': ['14px', { lineHeight: '1.6', fontWeight: '400' }],
        'body-md': ['13px', { lineHeight: '1.6', fontWeight: '400' }],
        'label-md': ['11px', { lineHeight: '1.4', letterSpacing: '0.5px', fontWeight: '500' }],
      },
      transitionDuration: {
        fast: '100ms',
        mid: '180ms',
        slow: '280ms',
      },
      keyframes: {
        'fade-in-up': {
          '0%': { opacity: '0', transform: 'translateY(20px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        'fade-in': {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        'float': {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-8px)' },
        },
        'glow-pulse': {
          '0%, 100%': { opacity: '0.4' },
          '50%': { opacity: '0.8' },
        },
        'cursor-blink': {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0' },
        },
      },
      animation: {
        'fade-in-up': 'fade-in-up 0.7s cubic-bezier(0.16, 1, 0.3, 1) forwards',
        'fade-in': 'fade-in 0.5s ease-out forwards',
        'float': 'float 5s ease-in-out infinite',
        'glow-pulse': 'glow-pulse 3s ease-in-out infinite',
        'cursor-blink': 'cursor-blink 1.2s step-end infinite',
      },
      backgroundImage: {
        'gradient-radial': 'radial-gradient(var(--tw-gradient-stops))',
      },
    },
  },
  plugins: [],
};
