/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        bg: '#101010',
        surface: '#181818',
        'surface-variant': '#202020',
        'surface-elevated': '#242424',
        border: '#323232',
        'border-subtle': '#272727',
        accent: '#E0E0E0',
        'accent-subtle': 'rgba(224, 224, 224, 0.1)',
        'on-accent': '#101010',
        foreground: '#F5F5F5',
        'foreground-muted': '#A1A1A1',
        'foreground-faint': '#606060',
        success: '#22C55E',
        error: '#F87171',
        'on-error': '#2C0D0D',
        warning: '#F59E0B',
      },
      borderRadius: {
        sm: '4px',
        md: '6px',
        lg: '10px',
        xl: '12px',
        pill: '20px',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
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
