<script lang="ts">
	// The studio's Button (shadcn-svelte), reduced to its base and ghost variant: every button on
	// this page is a ghost restyled at the call site. A link when given `href`.
	import type { Snippet } from 'svelte';

	let { href, variant = 'ghost', size = 'default', class: className = '', children, ...rest }: {
		href?: string;
		variant?: string;
		size?: 'default' | 'sm' | 'xs' | 'icon-sm';
		class?: string;
		children?: Snippet;
		[key: string]: unknown;
	} = $props();

	const SIZES = {
		default: 'h-9 px-4 py-2 text-sm font-medium rounded-md',
		sm: 'h-8 gap-1.5 px-3 text-sm font-medium rounded-md',
		xs: 'h-7 gap-1 px-2.5 text-xs font-medium rounded-md [&_svg]:size-3.5',
		'icon-sm': 'size-8 p-0 rounded-md [&_svg]:size-4'
	};
	const base =
		'inline-flex shrink-0 items-center justify-center gap-2 whitespace-nowrap border border-transparent cursor-pointer transition-all duration-200 outline-none select-none focus-visible:ring-2 focus-visible:ring-[var(--phonon-accent)]/40 disabled:cursor-not-allowed disabled:opacity-60 bg-transparent [&_svg]:pointer-events-none [&_svg]:shrink-0';
	const classes = $derived(`${base} ${SIZES[size]} ${className}`);
</script>

{#if href}
	<a {href} class={classes} {...rest}>{@render children?.()}</a>
{:else}
	<button type="button" class={classes} {...rest}>{@render children?.()}</button>
{/if}
