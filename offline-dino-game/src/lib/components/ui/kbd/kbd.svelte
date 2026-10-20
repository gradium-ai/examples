<script lang="ts">
	// The studio's Kbd: a key, as a small inset cap.
	import type { Snippet } from 'svelte';
	let { class: className = '', children }: { class?: string; children?: Snippet } = $props();
</script>

<kbd
	class="pointer-events-none inline-flex h-5 min-w-5 items-center justify-center rounded-sm border border-[var(--phonon-line)] bg-[var(--phonon-bezel)] px-1 font-mono text-[0.6875rem] font-medium text-[var(--phonon-ink)] select-none {className}"
	>{@render children?.()}</kbd
>
