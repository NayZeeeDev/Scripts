/** @type {import('tailwindcss').Config} */
const rgb = (v) => `rgb(var(${v}) / <alpha-value>)`;
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        accent: { DEFAULT: rgb('--accent'), hi: rgb('--accent-hi'), lo: rgb('--accent-lo') },
        ink: { DEFAULT: '#08090a', 2: '#0e1011', 3: '#15181a' },
        fg: { DEFAULT: '#eef1f2', 2: '#aab3b8', 3: '#6b757b', 4: '#454c51' },
        ok: '#3ddc84', warn: '#f5b84b', bad: '#ff5a5f', love: '#ff5f8f',
      },
      fontFamily: {
        display: ['"Barlow Condensed"', 'Barlow', 'sans-serif'],
        body: ['Barlow', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
      },
      transitionTimingFunction: { out: 'cubic-bezier(.22,.8,.26,1)' },
    },
  },
  plugins: [],
};
