<script lang="ts">
	// The studio's Hint (a tooltip naming a control and its key), as the browser's own tooltip.
	import type { Snippet } from 'svelte';
	let { label, keys = [], trigger }: {
		label: string;
		keys?: string[];
		side?: string;
		delayDuration?: number;
		trigger: Snippet<[{ props: Record<string, unknown> }]>;
	} = $props();
	const title = $derived(keys.length ? `${label} (${keys.join(' ')})` : label);
</script>

{@render trigger({ props: { title } })}
