<script lang="ts">
	// The studio's Slider (bits-ui), reduced to the one this page uses: a single horizontal value.
	// It renders the same `data-slot` parts, so the arcade's `arcade-fader` styles apply unchanged.
	import type { Snippet } from 'svelte';

	let {
		min = 0,
		max = 100,
		step = 1,
		value,
		onValueChange,
		thumbLabel,
		thumb,
		class: className = ''
	}: {
		type?: 'single';
		min?: number;
		max?: number;
		step?: number;
		value: number;
		onValueChange: (value: number) => void;
		thumbLabel?: string;
		thumb?: Snippet;
		class?: string;
	} = $props();

	let root: HTMLSpanElement;
	const percent = $derived(((value - min) / (max - min)) * 100);

	function set(next: number) {
		const clamped = Math.min(max, Math.max(min, Math.round(next / step) * step));
		if (clamped !== value) onValueChange(clamped);
	}

	function fromPointer(event: PointerEvent) {
		const box = root.getBoundingClientRect();
		set(min + ((event.clientX - box.left) / box.width) * (max - min));
	}

	function onpointerdown(event: PointerEvent) {
		root.setPointerCapture(event.pointerId);
		fromPointer(event);
	}

	function onkeydown(event: KeyboardEvent) {
		const delta = { ArrowLeft: -step, ArrowDown: -step, ArrowRight: step, ArrowUp: step, PageDown: -10 * step, PageUp: 10 * step }[event.key];
		if (event.key === 'Home') set(min);
		else if (event.key === 'End') set(max);
		else if (delta) set(value + delta);
		else return;
		event.preventDefault();
	}
</script>

<!-- The track takes the drag; the thumb is the slider (its role, value and keys). -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<span
	bind:this={root}
	data-slot="slider"
	class="relative flex w-full touch-none items-center select-none {className}"
	{onpointerdown}
	onpointermove={(e) => root.hasPointerCapture(e.pointerId) && fromPointer(e)}
>
	<span data-slot="slider-track" class="relative h-1 w-full grow overflow-hidden rounded-md">
		<span data-slot="slider-range" class="absolute h-full" style:width="{percent}%"></span>
	</span>
	<span
		data-slot="slider-thumb"
		role="slider"
		tabindex="0"
		aria-label={thumbLabel}
		aria-valuemin={min}
		aria-valuemax={max}
		aria-valuenow={value}
		class="absolute block shrink-0"
		style:left="calc({percent}% - 0.4375rem)"
		{onkeydown}
	>
		{@render thumb?.()}
	</span>
</span>
