import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    assetsDir: 'assets',
    target: 'chrome103',
    cssTarget: 'chrome103',
    sourcemap: false,
    chunkSizeWarningLimit: 600,
  },
  server: { port: 5173, host: true },
  preview: { port: 4173 },
});
