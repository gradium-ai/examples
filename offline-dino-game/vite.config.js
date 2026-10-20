import { readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import tailwindcss from '@tailwindcss/vite';

// Cross-origin isolation turns on SharedArrayBuffer, so Phonon runs on its threaded wasm build.
const ISOLATION = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
};

// For a build: the list of page files the service worker saves on the first visit (precache.json).
// Phonon's weights are not among them: they come from Hugging Face (src/voice.js).
function offlineBuild() {
  return {
    name: 'offline-build',
    apply: 'build',
    generateBundle(_, bundle) {
      const files = Object.keys(bundle).filter((f) => f !== 'index.html');
      // Everything in public/ too, except the worker itself.
      const pub = resolve(import.meta.dirname, 'public');
      const statics = readdirSync(pub, { recursive: true })
        .filter((f) => f !== 'sw.js' && statSync(join(pub, f)).isFile());
      // Relative to the page: the service worker resolves them against its own scope.
      const urls = ['./', ...files, ...statics];
      this.emitFile({ type: 'asset', fileName: 'precache.json', source: JSON.stringify({ urls }, null, 2) });
    },
  };
}

export default defineConfig({
  // Relative URLs, so a build runs from any sub-path, such as gradium.ai/demos/phonon-in-browser/.
  base: './',
  plugins: [svelte(), tailwindcss(), offlineBuild()],
  // The studio's `$lib`, for the components copied from it (src/arcade/, src/lib/).
  resolve: { alias: { $lib: resolve(import.meta.dirname, 'src/lib') } },
  server: { headers: ISOLATION, port: 5190, strictPort: true, host: '127.0.0.1' },
  preview: { headers: ISOLATION, port: 5190, strictPort: true, host: '127.0.0.1' },
  worker: { format: 'es' },
  optimizeDeps: { exclude: ['phonon-tts'] },
  build: { target: 'es2022' },
});
