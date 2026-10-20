import './app.css';
import { mount } from 'svelte';
import OfflineFm from './OfflineFm.svelte';

let started = false;   // the page is in use: never reload under the player
addEventListener('pointerdown', () => (started = true), { once: true, capture: true });
addEventListener('keydown', () => (started = true), { once: true, capture: true });

// In a build, a service worker saves every page file on the first visit, so the page reopens with
// no network. It also adds the headers Phonon's threads need, for hosts that cannot set them: on
// such a host the page reloads once, before setup starts, to pick them up.
// The dev server runs on this machine and needs no such copy, and a stale one would hide edits,
// so in dev any worker left from a build is removed.
// Paths are relative to the page, so the game works under a sub-path (gradium.ai/demos/…/).
if ('serviceWorker' in navigator) {
  if (import.meta.env.PROD) {
    navigator.serviceWorker.register('sw.js')
      .then(() => navigator.serviceWorker.ready)
      .then(() => {
        if (crossOriginIsolated || started || once('isolation-reload')) return;
        location.reload();
      })
      .catch((err) => console.warn('[sw]', err));
  } else {
    navigator.serviceWorker.getRegistrations().then(async (regs) => {
      if (!regs.length) return;
      await Promise.all(regs.map((r) => r.unregister()));
      for (const key of await caches.keys()) if (key.startsWith('offline-fm-')) await caches.delete(key);
      location.reload();
    });
  }
}

/** True if `key` was already used in this tab; marks it used. */
function once(key) {
  try {
    if (sessionStorage.getItem(key)) return true;
    sessionStorage.setItem(key, '1');
    return false;
  } catch {
    return true;   // no storage: never risk a reload loop
  }
}

mount(OfflineFm, { target: document.getElementById('app') });
