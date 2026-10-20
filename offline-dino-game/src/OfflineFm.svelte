<script lang="ts">
	/**
	 * Offline FM in the Phonon arcade cabinet. The cabinet (the room, the marquee, the screen in
	 * its bezel, the control deck, the kick panel) is the studio's Phonon page, gradium-ai/studio
	 * `src/routes/models/text-to-speech/on-device/arcade/ArcadePage.svelte`, cut down to its Offline
	 * FM screen. What differs: Rex's voice is Phonon running in this tab (`voice.js`), not the API,
	 * and his show is this demo's (`podcast.js`, `lines.js`).
	 */
	import { onMount } from 'svelte';
	import { Button } from '$lib/components/ui/button';
	import { Slider } from '$lib/components/ui/slider';
	import { Hint } from '$lib/components/ui/tooltip';
	import { t } from '$lib/i18n';
	import type { MessageKey } from '$lib/i18n';
	import PhononRunner from './arcade/PhononRunner.svelte';
	import HalftoneGrille from './arcade/HalftoneGrille.svelte';
	import HalftoneBackdrop from './arcade/HalftoneBackdrop.svelte';
	import ArcadeRoom from './arcade/ArcadeRoom.svelte';
	import IconHuggingFace from './arcade/IconHuggingFace.svelte';
	import { reducedMotion } from './arcade/halftone';
	import { ArcadeAmbience } from './arcade/ambience';
	import { marquee } from './arcade/marquee';
	import { Sfx } from './arcade/sfx';
	import type { GameEvent } from './arcade/types';
	import { loadPhonon, Speaker, VOICES } from './voice.js';
	import { Podcast } from './podcast.js';
	import { TOPICS } from './lines.js';
	import IconArrowLeft from '@tabler/icons-svelte/icons/arrow-left';
	import IconArrowUpRight from '@tabler/icons-svelte/icons/arrow-up-right';
	import IconBrandGithub from '@tabler/icons-svelte/icons/brand-github';
	import IconChevronLeft from '@tabler/icons-svelte/icons/chevron-left';
	import IconChevronRight from '@tabler/icons-svelte/icons/chevron-right';
	import IconHome from '@tabler/icons-svelte/icons/home';
	import IconVolume from '@tabler/icons-svelte/icons/volume';
	import IconVolumeOff from '@tabler/icons-svelte/icons/volume-off';
	import IconWorld from '@tabler/icons-svelte/icons/world';

	const STUDIO_URL = 'https://gradium.ai/studio';
	/** The studio's `PHONON_LINKS` ($lib/phonon), with GitHub pointing at this game's code. */
	const PHONON_LINKS = {
		website: 'https://gradium.ai/phonon',
		github: 'https://github.com/gradium-ai/examples/tree/main/offline-dino-game',
		huggingFace: 'https://huggingface.co/gradium/phonon-31m-en'
	};
	type PhononLink = keyof typeof PHONON_LINKS;
	const PHONON_MB = 65;

	// ---- Voices: Phonon's own, in this tab --------------------------------------------

	const params = new URLSearchParams(location.search);
	let voice = $state(VOICES.includes(params.get('voice') ?? '') ? params.get('voice')! : VOICES[0]);

	function useVoice(next: string) {
		voice = next;
		podcast?.setVoice(next);
	}

	/** ← and →, or the arrows either side of the picker: the next fighter. */
	function cycleVoice(delta: -1 | 1) {
		const at = VOICES.indexOf(voice);
		useVoice(VOICES[(at + delta + VOICES.length) % VOICES.length]);
		sfx?.select();
	}

	// ---- The machine -------------------------------------------------------------------

	/** Off until a press turns it on; M or the corner toggle after that. */
	let soundOn = $state(false);
	let credits = $state(0);
	/** Bumped when the screen changes: it flashes once, as a tube does. */
	let flashes = $state(0);
	/** Bumped by TITLE SCREEN: the runner starts over on its START GAME screen. */
	let runKey = $state(0);

	let ctx: AudioContext | null = null;
	/** The cabinet is on: audio unlocked and Phonon loading or loaded. */
	let powered = $state(false);
	/** The deck's fader: everything the cabinet plays goes through it. */
	let master: GainNode | null = null;
	let speaker: Speaker | null = null;
	let podcast: Podcast | null = null;
	let sfx = $state<Sfx | null>(null);
	let rexOut = $state.raw<AnalyserNode | null>(null);

	/** The analyser sits before the fader: the grille shows the voice, not the level. */
	function analyserOn(audio: AudioContext, out: AudioNode): AnalyserNode {
		const node = audio.createAnalyser();
		node.fftSize = 256;
		node.smoothingTimeConstant = 0.55;
		node.connect(out);
		return node;
	}

	/**
	 * Audio is built on the first press, never before. The same press starts Phonon's download
	 * (65 MB, then from the browser's cache); the game can be played while it loads, and Rex
	 * comes on air when it is ready.
	 */
	function powerUp() {
		if (!ctx) {
			ctx = new AudioContext();
			powered = true;
			master = ctx.createGain();
			master.gain.value = loudness(volume);
			master.connect(ctx.destination);
			rexOut = analyserOn(ctx, master);
			sfx = new Sfx(ctx, master);
			ambience = new ArcadeAmbience(ctx, master);
			navigator.storage?.persist?.().catch(() => {});
			void tuneIn();
		}
		resume();
		if (!soundOn) setSound(true);
	}

	let loading = $state<string | null>(null);

	async function tuneIn() {
		if (!ctx || !rexOut) return;
		loading = $t('phonon.show.warmingUp');
		try {
			const tts = await loadPhonon((fraction: number, bytes: number) => {
				loading = fraction >= 1 ? 'Warming up the voice' : `Loading Phonon · ${Math.round(bytes / 1e6)} of ${PHONON_MB} MB`;
			});
			speaker = new Speaker(tts, ctx, rexOut);
			speaker.voice = voice;
			speaker.setMuted(!soundOn);
			podcast = new Podcast({ speaker, onError: signalLost });
			await podcast.prepareYelps(voice);
			loading = null;
			podcast.start();
		} catch (error) {
			console.error('[offline-fm]', error);
			loading = `Rex could not load Phonon: ${(error as Error).message || error}`;
		}
	}

	function signalLost(message: string) {
		console.warn('[offline-fm]', message);
		lostSignal = true;
		setTimeout(() => (lostSignal = false), 4000);
	}

	function setSound(on: boolean) {
		soundOn = on;
		speaker?.setMuted(!on);
		if (sfx) sfx.muted = !on;
		syncAmbience();
	}

	// ---- The fader: the deck's master volume --------------------------------------------

	const VOLUME_KEY = 'phonon-arcade-volume';
	/** 0 to 100, beside START. Remembered in this browser. */
	let volume = $state(80);
	/** Heard as its square: a fader's travel is closer to loudness than to gain. */
	const loudness = (v: number) => (v / 100) ** 2;

	function setVolume(next: number) {
		volume = next;
		master?.gain.setTargetAtTime(loudness(next), master.context.currentTime, 0.03);
		try {
			localStorage.setItem(VOLUME_KEY, String(next));
		} catch {
			// A private window: the level lasts as long as the page.
		}
		// Pushing the fader up is a press asking to hear: the sound comes on with it.
		if (next > 0 && (!ctx || !soundOn)) {
			const cold = !ctx;
			powerUp();
			if (cold) sfx?.powerOn();
		}
	}

	// ---- The room: the arcade's ambience ----------------------------------------------

	let ambience: ArcadeAmbience | null = null;

	/** The room plays whenever the sound is on: one SOUND toggle (M) for both. */
	function syncAmbience() {
		ambience?.setEnabled(soundOn && !document.hidden);
	}

	// Under a voice, the room steps back.
	$effect(() => {
		ambience?.duck(speaking);
	});

	// ---- The eye: the scene's perspective, following the pointer --------------------

	/** One perspective for the room and the cabinet, so they read as one space. */
	const PERSPECTIVE = 1000;
	/** Where the eye sits off centre, in px: a step to either side, never a zoom. */
	let eye = $state({ x: 0, y: 0 });
	let aimAt = { x: 0, y: 0 };
	let aimFrame = 0;

	function aim(event: PointerEvent) {
		if (event.pointerType !== 'mouse' || reducedMotion()) return;
		aimAt = {
			x: (event.clientX / window.innerWidth - 0.5) * 2 * 150,
			y: (event.clientY / window.innerHeight - 0.5) * 2 * 60
		};
		if (!aimFrame) aimFrame = requestAnimationFrame(follow);
	}

	function follow() {
		const dx = aimAt.x - eye.x;
		const dy = aimAt.y - eye.y;
		if (Math.abs(dx) < 0.2 && Math.abs(dy) < 0.2) {
			aimFrame = 0;
			return;
		}
		eye = { x: eye.x + dx * 0.08, y: eye.y + dy * 0.08 };
		aimFrame = requestAnimationFrame(follow);
	}

	/** Where the cabinet stands in the page, for the room to put its floor under it. */
	let wrap = $state<HTMLDivElement>();
	let scene = $state<HTMLDivElement>();
	let room = $state({ eyeY: 0, box: { left: 0, right: 0, top: 0, bottom: 0 } });
	/** How far the cabinet's side panels come toward the eye: the deck's reach, and a bit. */
	const CABINET_DEPTH = 110;

	function measure() {
		if (!wrap || !scene) return;
		const w = wrap.getBoundingClientRect();
		const r = scene.getBoundingClientRect();
		room = {
			eyeY: r.top - w.top + r.height * 0.4,
			box: { left: r.left - w.left, right: r.right - w.left, top: r.top - w.top, bottom: r.bottom - w.top }
		};
	}

	function toggleSound() {
		(document.activeElement as HTMLElement | null)?.blur();
		if (!ctx) {
			powerUp();
			sfx?.powerOn();
			return;
		}
		setSound(!soundOn);
		if (soundOn) sfx?.clack();
	}

	/** The coin door: a coin for the cabinet, and the runner takes it as one too (its C). */
	function insertCoin() {
		powerUp();
		// The C it sends counts the coin (onPageKey), as the keyboard's C does.
		press(K.c, 'keydown');
		press(K.c, 'keyup');
	}

	/** TITLE SCREEN: the runner back to START GAME, the tube flashing as it changes. */
	function toTitle() {
		(document.activeElement as HTMLElement | null)?.blur();
		runKey++;
		flashes++;
		sfx?.select();
	}

	// ---- Offline FM ----------------------------------------------------------------------

	let topic = $state<string | null>(null);
	let caption = $state('');
	let speaking = $state(false);
	let lostSignal = $state(false);
	/** The HUD's top line, measured here: what Rex has voiced, and his quickest first audio. */
	let voiced = $state(0);
	let quickest = $state<number | null>(null);
	let idleTimer: ReturnType<typeof setTimeout> | undefined;

	function onGameEvent(event: GameEvent) {
		powerUp();
		podcast?.gameEvent(event);
		clearTimeout(idleTimer);
		if (event.type === 'over') {
			idleTimer = setTimeout(() => podcast?.gameEvent({ type: 'idle' }), 15_000);
		}
	}

	function resume() {
		if (ctx && ctx.state !== 'running') void ctx.resume();
	}

	function chooseTopic(id: string) {
		(document.activeElement as HTMLElement | null)?.blur();
		topic = topic === id ? null : id;
		podcast?.setTopic(topic);
	}

	// ---- Keys ----------------------------------------------------------------------------

	function typingIn(target: EventTarget | null): boolean {
		return !!(target as HTMLElement | null)?.closest(
			'input, textarea, select, [contenteditable], [role="combobox"], [role="listbox"], [role="menu"], [role="dialog"], [role="slider"]'
		);
	}

	/** The keys held down right now, by code: their buttons on the cabinet go down with them. */
	let held = $state<Record<string, boolean>>({});

	function onKeyUp(event: KeyboardEvent) {
		delete held[event.code];
	}

	/** A key let go while the window had lost focus never says so. */
	function releaseAll() {
		held = {};
	}

	function onPageKey(event: KeyboardEvent) {
		const target = event.target as HTMLElement | null;
		if (!typingIn(target)) held[event.code] = true;
		if (typingIn(target) || event.metaKey || event.ctrlKey || event.altKey) return;
		if ((event.code === 'Space' || event.code === 'Enter') && target?.closest('button, a')) return;

		const code = event.code;
		if (code === 'KeyM') return toggleSound();
		// Any other key is a press: it wakes the cabinet (audio needs one) and starts Phonon.
		powerUp();
		if (code === 'KeyC') credits = Math.min(99, credits + 1);
		if (code === 'Digit0' && !event.shiftKey) return toTitle();
		// Shift + a number is a topic; the runner owns Space, the arrows, P, Esc and C.
		const digit = /^Digit([1-5])$/.exec(code);
		if (digit && event.shiftKey) chooseTopic(TOPIC_IDS[Number(digit[1]) - 1]);
	}

	// ---- Copy tables ---------------------------------------------------------------------

	const LINKS: { id: PhononLink; key: MessageKey; sticker: MessageKey; Icon: any }[] = [
		{ id: 'github', key: 'phonon.links.github', sticker: 'phonon.sticker.github', Icon: IconBrandGithub },
		{ id: 'huggingFace', key: 'phonon.links.huggingFace', sticker: 'phonon.sticker.huggingFace', Icon: IconHuggingFace },
		{ id: 'website', key: 'phonon.links.website', sticker: 'phonon.sticker.website', Icon: IconWorld }
	];
	/** The maker's plaque's serial: the model's version, an identifier, not copy. */
	const PLAQUE_SERIAL = 'GR1.0';

	/**
	 * The stickers on the kick panel, no two alike, each slapped on at its own angle, all three
	 * lime: a label (GitHub), a round badge in the dot-matrix face (Hugging Face), and a tag with
	 * its punched hole (gradium.ai), down by the coin door.
	 */
	const STICKER: Record<PhononLink, { look: string; face: 'mono' | 'komuna' | 'tag' }> = {
		github: {
			look: 'rounded-md! px-3! py-1.5! bg-[var(--phonon-accent)]! hover:bg-[var(--phonon-accent)]! text-[0.6875rem]! font-semibold tracking-[0.08em] uppercase -rotate-6 translate-y-3 max-md:translate-y-0',
			face: 'mono'
		},
		huggingFace: {
			look: 'rounded-full! px-5! py-2.5! bg-[var(--phonon-accent)]! hover:bg-[var(--phonon-accent)]! outline-1 outline-dashed -outline-offset-[6px] outline-[color-mix(in_srgb,var(--phonon-accent-deep)_45%,transparent)] rotate-[5deg] translate-y-1 max-md:translate-y-0',
			face: 'komuna'
		},
		website: {
			look: 'rounded-l-[1.1rem]! rounded-r-sm! pl-2.5! pr-3! py-1.5! bg-[var(--phonon-accent)]! hover:bg-[var(--phonon-accent)]! text-xs! font-medium -rotate-3',
			face: 'tag'
		}
	};

	const TOPIC_IDS = Object.keys(TOPICS);

	/** The cabinet's buttons beside the tube. Here only the title screen and Offline FM. */
	const STAGES = [
		{ id: 'attract', key: '0', label: 'phonon.cabinet.title', hint: 'phonon.cabinet.homeHint' },
		{ id: 'game', key: '2', label: 'phonon.mode.game', hint: 'phonon.mode.gameHint' }
	] as const;

	// ---- The deck: each key the screen answers, as a button on the panel ---------

	/** A key, as the deck's button sends it: the code the page and the runner read. */
	type DeckKey = { code: string; key: string; glyph: string };
	const K = {
		space: { code: 'Space', key: ' ', glyph: 'Space' },
		left: { code: 'ArrowLeft', key: 'ArrowLeft', glyph: '←' },
		right: { code: 'ArrowRight', key: 'ArrowRight', glyph: '→' },
		down: { code: 'ArrowDown', key: 'ArrowDown', glyph: '↓' },
		p: { code: 'KeyP', key: 'p', glyph: 'P' },
		c: { code: 'KeyC', key: 'c', glyph: 'C' },
		m: { code: 'KeyM', key: 'm', glyph: 'M' }
	} satisfies Record<string, DeckKey>;
	type Control = { keys: DeckKey[]; label: MessageKey };
	const CONTROLS: Control[] = [
		{ keys: [K.space], label: 'phonon.keys.jump' },
		{ keys: [K.down], label: 'phonon.keys.duck' },
		{ keys: [K.left, K.right], label: 'phonon.keys.choose' },
		{ keys: [K.p], label: 'phonon.keys.pause' },
		{ keys: [K.c], label: 'phonon.keys.coin' },
		{ keys: [K.m], label: 'phonon.keys.sound' }
	];

	/**
	 * A deck button is its key: it sends the key the keyboard would, from the page, so the page
	 * and the runner answer it exactly as they answer the keyboard (a held ↓ ducks until it is let
	 * go). From the body rather than the button, which both of them ignore keys from.
	 */
	function press(key: DeckKey, type: 'keydown' | 'keyup') {
		document.body.dispatchEvent(new KeyboardEvent(type, { code: key.code, key: key.key, bubbles: true, cancelable: true }));
	}

	const pad = (n: number, digits = 5) => String(Math.min(n, 10 ** digits - 1)).padStart(digits, '0');
	const seconds = (ms: number) => (ms / 1000).toFixed(3);

	// ---- Lifecycle -----------------------------------------------------------------------

	onMount(() => {
		try {
			const stored = Number(localStorage.getItem(VOLUME_KEY) ?? NaN);
			if (Number.isFinite(stored)) volume = Math.min(100, Math.max(0, Math.round(stored)));
		} catch {
			// No storage: the fader's default.
		}
		// A cabinet in a background tab keeps the room to itself.
		const onVisibility = () => syncAmbience();
		document.addEventListener('visibilitychange', onVisibility);
		const sizes = new ResizeObserver(measure);
		if (wrap) sizes.observe(wrap);
		if (scene) sizes.observe(scene);

		// The caption follows whatever Rex is saying, line by line.
		let lastLine: unknown = null;
		const captionTimer = setInterval(() => {
			const line = speaker?.current() ?? null;
			speaking = !!line;
			const first = speaker?.lastFirstAudioMs;
			if (first != null) quickest = quickest === null ? first : Math.min(quickest, first);
			if (line && line !== lastLine) {
				lastLine = line;
				caption = line.text;
				voiced += line.text.length;
			}
		}, 80);

		return () => {
			clearInterval(captionTimer);
			clearTimeout(idleTimer);
			document.removeEventListener('visibilitychange', onVisibility);
			sizes.disconnect();
			cancelAnimationFrame(aimFrame);
			ambience?.dispose();
			void ctx?.close();
		};
	});
</script>

<svelte:window onkeydown={onPageKey} onkeyup={onKeyUp} onblur={releaseAll} onpointermove={aim} />

<!-- Text set in Komuna, the dot-matrix face, always at a stated thin weight and through
     `marquee()`: it has no accented letters. -->
{#snippet komuna(text: string, cls = '')}
	<span class="font-komuna font-thin tracking-[0.2em] uppercase {cls}">{marquee(text)}</span>
{/snippet}

<!-- One of the cabinet's screen buttons beside the tube, named under its cap. Pressed in and lit
     lime: the screen showing now. -->
{#snippet screenButton(s: (typeof STAGES)[number])}
	{@const current = s.id === 'game'}
	<Hint label={$t(s.hint)} keys={[s.key]} side="left">
		{#snippet trigger({ props })}
			<Button
				{...props}
				variant="ghost"
				aria-pressed={current}
				onclick={() => (current ? undefined : toTitle())}
				class="group h-auto! flex-col gap-1.5! rounded-none! border-transparent! bg-transparent! p-0! font-mono whitespace-normal! hover:bg-transparent!"
			>
				<span class="flex size-12 shrink-0 items-center justify-center rounded-full bg-[var(--phonon-cabinet)] pb-1">
					<span
						class="flex size-9 items-center justify-center rounded-full text-caption font-medium transition-transform duration-75 {current
							? 'arcade-key-down translate-y-0.5 text-[var(--phonon-accent-deep)] [--cap:var(--phonon-accent)]'
							: `arcade-key text-[var(--phonon-ink)] [--cap:var(--phonon-key)] [--lift:0.3rem] group-active:translate-y-0.5 group-active:shadow-none ${held[`Digit${s.key}`] ? 'translate-y-0.5 shadow-none!' : '-translate-y-1'}`}"
					>
						{#if s.id === 'attract'}
							<IconHome class="size-4" stroke={2} />
						{:else}
							{s.key}
						{/if}
					</span>
				</span>
				<span class="max-w-28 text-center text-[0.625rem] leading-tight tracking-[0.06em] uppercase max-md:max-w-20 max-md:text-[0.5625rem] {current ? 'text-[var(--phonon-ink)]' : 'text-[var(--phonon-ink-muted)]'}">{$t(s.label)}</span>
			</Button>
		{/snippet}
	</Hint>
{/snippet}

<!-- One of the deck's controls: its key's cap (two for a pair of arrows, a long bar for Space)
     in a well on the panel, its name engraved under it. Pressing it sends the key; held, it holds
     the key. -->
{#snippet control(c: Control)}
	<div class="flex flex-col items-center gap-1.5" role={c.keys.length > 1 ? 'group' : undefined} aria-label={c.keys.length > 1 ? $t(c.label) : undefined}>
		<span class="flex items-center gap-1 rounded-full bg-[var(--phonon-cabinet)] p-1 pb-1.5">
			{#each c.keys as k, i (k.code)}
				<Button
					variant="ghost"
					aria-label={c.keys.length > 1 ? $t(i === 0 ? 'phonon.cabinet.left' : 'phonon.cabinet.right') : $t(c.label)}
					aria-keyshortcuts={k.code === 'Space' ? 'Space' : k.key}
					onpointerdown={(event: PointerEvent) => {
						event.preventDefault();
						powerUp();
						press(k, 'keydown');
					}}
					onpointerup={() => press(k, 'keyup')}
					onpointerleave={() => press(k, 'keyup')}
					onpointercancel={() => press(k, 'keyup')}
					onkeydown={(event: KeyboardEvent) => {
						if (event.key !== 'Enter' && event.key !== ' ') return;
						event.preventDefault();
						press(k, 'keydown');
						press(k, 'keyup');
					}}
					class="group h-auto! rounded-full! border-transparent! bg-transparent! p-0! hover:bg-transparent!"
				>
					<span
						class="arcade-key flex h-8 items-center justify-center rounded-full font-mono text-[0.6875rem] font-medium transition-transform duration-75 [--cap:var(--phonon-key)] [--lift:0.3rem] group-active:translate-y-0.5 group-active:shadow-none {k.code ===
						'Space'
							? 'w-16'
							: 'w-8'} {held[k.code] ? 'translate-y-0.5 text-[var(--phonon-accent)] shadow-none!' : '-translate-y-1 text-[var(--phonon-ink)]'}"
					>
						{k.glyph}
					</span>
				</Button>
			{/each}
		</span>
		<span class="arcade-engraved max-w-24 text-center text-[0.5625rem] leading-tight tracking-[0.12em] text-[var(--phonon-ink-muted)] uppercase" aria-hidden="true">{$t(c.label)}</span>
	</div>
{/snippet}

<!-- A link out, as a sticker on the kick panel (see `STICKER`): a white die-cut edge round
     each, its own shape, face and angle. Pointed at, it stays put; only its words underline. -->
{#snippet sticker(link: (typeof LINKS)[number])}
	{@const { look, face } = STICKER[link.id]}
	<Button
		href={PHONON_LINKS[link.id]}
		target="_blank"
		rel="noopener noreferrer"
		variant="ghost"
		class="relative h-auto! shrink-0 gap-2! border-2! border-[var(--phonon-ink)]! font-mono text-[var(--phonon-accent-deep)]! shadow-[0_0.2rem_0_color-mix(in_srgb,var(--phonon-bg)_60%,transparent)] underline-offset-2 hover:underline {look}"
	>
		{#if face === 'tag'}
			<span class="size-2 shrink-0 rounded-full bg-[var(--phonon-bezel)] ring-1 ring-[color-mix(in_srgb,var(--phonon-accent-deep)_40%,transparent)]" aria-hidden="true"></span>
		{/if}
		<link.Icon class="size-4" />
		{#if face === 'komuna'}
			{@render komuna($t(link.sticker), 'text-[0.6875rem] font-[200] tracking-[0.15em]')}
		{:else}
			<span>{$t(link.sticker)}</span>
		{/if}
		<span class="sr-only">({$t(link.key)})</span>
		<IconArrowUpRight class="size-3.5 shrink-0" />
	</Button>
{/snippet}

{#snippet voicePicker()}
	<div class="flex items-center gap-1">
		<Button
			variant="ghost"
			size="icon-sm"
			aria-label={$t('phonon.stage1.prevVoice')}
			onclick={() => cycleVoice(-1)}
			class="rounded-none! text-[var(--phonon-ink-muted)] hover:bg-[var(--phonon-ink)]! hover:text-[var(--phonon-bg)]!"
		>
			<IconChevronLeft class="size-4" />
		</Button>
		<select
			value={voice}
			onchange={(e) => useVoice((e.currentTarget as HTMLSelectElement).value)}
			aria-label={$t('phonon.stage1.voice')}
			class="h-8 w-48 rounded-none border border-[var(--phonon-line)] bg-[var(--phonon-bg)] px-2 font-mono text-sm text-[var(--phonon-ink)] max-md:w-40"
		>
			{#each VOICES as name (name)}
				<option value={name}>{name}</option>
			{/each}
		</select>
		<Button
			variant="ghost"
			size="icon-sm"
			aria-label={$t('phonon.stage1.nextVoice')}
			onclick={() => cycleVoice(1)}
			class="rounded-none! text-[var(--phonon-ink-muted)] hover:bg-[var(--phonon-ink)]! hover:text-[var(--phonon-bg)]!"
		>
			<IconChevronRight class="size-4" />
		</Button>
	</div>
{/snippet}

<div class="relative h-svh overflow-x-hidden overflow-y-auto bg-[var(--phonon-bg)] font-mono text-[var(--phonon-ink)]">
	<!-- On a phone, where there is no room in 3D, the halftone rings stand in for it. -->
	<div class="md:hidden"><HalftoneBackdrop /></div>

	<div bind:this={wrap} class="relative flex min-h-full flex-col">
		<ArcadeRoom {eye} eyeY={room.eyeY} box={room.box} depth={CABINET_DEPTH} perspective={PERSPECTIVE} />

		<!-- The room's corners: the way out, and all sound. Each on a knocked-out black ground, so
		     the print behind never runs through the words. -->
		<header class="relative z-20 flex items-center justify-between gap-3 px-5 pt-4 max-md:px-3 max-md:pt-3 lg:absolute lg:inset-x-0 lg:top-0">
			<Button
				href={STUDIO_URL}
				variant="ghost"
				size="xs"
				class="rounded-none! bg-[var(--phonon-bg)]! font-mono font-normal tracking-[0.12em] text-[var(--phonon-ink-muted)] uppercase hover:bg-[var(--phonon-ink)]! hover:text-[var(--phonon-bg)]!"
			>
				<IconArrowLeft class="size-3.5" />
				{$t('phonon.back')}
			</Button>
			<Hint label={$t('phonon.keys.sound')} keys={['M']}>
				{#snippet trigger({ props })}
					<Button
						{...props}
						variant="ghost"
						size="xs"
						aria-pressed={soundOn}
						onclick={toggleSound}
						class="rounded-none! bg-[var(--phonon-bg)]! font-mono font-normal tracking-[0.12em] uppercase {soundOn
							? 'text-[var(--phonon-ink)]!'
							: 'text-[var(--phonon-ink-muted)]'} hover:bg-[var(--phonon-ink)]! hover:text-[var(--phonon-bg)]!"
					>
						{#if soundOn}
							<IconVolume class="size-3.5 text-[var(--phonon-accent)]" />
						{:else}
							<IconVolumeOff class="size-3.5" />
						{/if}
						<span class="max-md:sr-only">{$t(soundOn ? 'phonon.cabinet.soundOn' : 'phonon.cabinet.soundOff')}</span>
					</Button>
				{/snippet}
			</Hint>
		</header>

		<main class="flex flex-1 flex-col items-center justify-center px-16 pt-10 pb-12 short:pt-8 short:pb-10 max-lg:px-10 max-lg:pt-8 max-lg:pb-7 max-md:px-2 max-md:pt-1 max-md:pb-6">
			<!-- The scene: the room's perspective and eye, the pointer moving the eye a step to either
			     side. Only things with depth move with it (the walls, the marquee, the deck); the
			     screen sits on the plane that perspective leaves alone, so its text never goes soft. -->
			<div
				bind:this={scene}
				class="relative z-10 mx-auto w-full max-w-[51rem] max-md:[perspective:none]!"
				style:perspective="{PERSPECTIVE}px"
				style:perspective-origin="calc(50% + {eye.x}px) calc(40% + {eye.y}px)"
			>
				<div class="relative [--deck:6.5rem] [--tilt:42deg] [transform-style:preserve-3d] short:[--deck:5.75rem]">
					<!-- The marquee, leaning out over the player. -->
					<div
						class="relative flex origin-bottom items-center justify-between gap-4 overflow-hidden rounded-t-xl bg-[var(--phonon-bezel)] px-7 py-3.5 [transform:rotateX(-16deg)] short:py-2 max-md:rounded-t-2xl max-md:px-4 max-md:py-2.5 max-md:[transform:none]"
					>
						<span class="arcade-dots pointer-events-none absolute inset-0 opacity-60" aria-hidden="true"></span>
						<span class="pointer-events-none absolute inset-x-0 bottom-0 h-1 bg-[var(--phonon-accent)]" aria-hidden="true"></span>
						<Button variant="ghost" class="relative h-auto! rounded-none! p-0! hover:bg-transparent!" aria-label={$t('phonon.cabinet.title')} onclick={toTitle}>
							<span class="arcade-misprint font-komuna text-xl font-thin tracking-[0.3em] text-[var(--phonon-ink)] uppercase max-md:text-base" aria-label="Phonon">
								Pho<span class="text-[var(--phonon-accent)]">non</span>
							</span>
						</Button>
						<h1 class="relative m-0 text-right">
							{@render komuna($t('phonon.tagline'), 'text-sm text-[var(--phonon-ink-muted)] max-md:text-[0.625rem] max-md:tracking-[0.1em]')}
						</h1>
					</div>

					<!-- The front: the tube in its bezel, and the cabinet's own buttons on the right. The tube is
					     at least 32.5rem tall (the studio's is 26rem), so Offline FM's runner, caption and topics fit
					     under the HUD instead of running into it on a short window. -->
					<div class="relative flex items-stretch bg-[var(--phonon-bezel)] [transform-style:preserve-3d] max-md:flex-col">
						<span class="arcade-dots pointer-events-none absolute inset-0 opacity-30" aria-hidden="true"></span>
						<div class="min-w-0 flex-1 p-4 pr-0 max-md:p-2">
							<div class="rounded-[1.4rem] bg-[var(--phonon-cabinet)] p-1.5 max-md:rounded-xl max-md:p-1">
								<div
									class="relative isolate flex h-[clamp(32.5rem,calc(100svh-29rem),37rem)] flex-col overflow-hidden rounded-[1.25rem] bg-[var(--phonon-screen)] short:h-[clamp(32.5rem,calc(100svh-26rem),37rem)] max-md:h-auto max-md:min-h-[34rem] max-md:rounded-xl"
								>
									<!-- HUD: the top line every cabinet has, in this tab's own numbers. -->
									<div class="arcade-glow relative z-10 grid shrink-0 grid-cols-3 items-start px-6 pt-4 max-md:px-3 max-md:pt-3">
										<div class="flex flex-col gap-0.5" aria-label="Characters Rex has voiced: {voiced}">
											{@render komuna($t('phonon.arcade.player'), 'text-caption text-[var(--phonon-accent)]')}
											<span class="text-sm tabular-nums" aria-hidden="true">{pad(voiced)}</span>
										</div>
										<div class="flex flex-col items-center gap-0.5" aria-label="Rex's quickest first audio">
											{@render komuna($t('phonon.arcade.hiScore'), 'text-caption text-[var(--phonon-arcade-sun)]')}
											<span class="text-sm tabular-nums">
												{quickest === null ? '-.--- s' : $t('phonon.hud.seconds', { seconds: seconds(quickest) })}
											</span>
										</div>
									</div>

									<!-- Offline FM: the runner, what Rex is saying, the topics. -->
									<div class="relative z-10 flex min-h-0 flex-1 flex-col px-6 pt-3 pb-5 max-md:px-3 max-md:pb-4">
										<div class="flex min-h-0 flex-1 flex-col justify-center gap-3 short:gap-1.5">
											<div class="flex flex-wrap items-center justify-between gap-2">
												{@render komuna($t('phonon.mode.game'), 'text-caption text-[var(--phonon-ink-muted)]')}
												{@render voicePicker()}
											</div>

											<div class="relative grayscale">
												{#key runKey}
													<PhononRunner onevent={onGameEvent} {sfx} />
												{/key}
												{#if !powered}
													<Button
														variant="ghost"
														class="absolute! inset-0 h-auto! items-end! rounded-none! bg-black/40! pb-6 hover:bg-black/30!"
														onclick={powerUp}
													>
														<span class="bg-[var(--phonon-ink)] px-3 py-1.5 text-caption text-[var(--phonon-bg)]">{$t('phonon.show.tuneIn')}</span>
													</Button>
												{/if}
											</div>

											<!-- What Rex is saying, as he says it; the meter is the grille, small. -->
											<div
												class="flex min-h-12 items-center gap-3 border border-[var(--phonon-line)] px-3 py-2 short:min-h-9 short:py-1"
												aria-live="polite"
											>
												<HalftoneGrille analyser={rexOut} active={speaking} class="h-7 w-16 shrink-0" />
												<p class="m-0 text-sm leading-snug {speaking ? 'arcade-glow text-[var(--phonon-ink)]' : 'text-[var(--phonon-ink-muted)]'}">
													{#if lostSignal}
														{$t('phonon.show.lostSignal')}
													{:else if loading}
														{loading}
													{:else}
														{caption || $t('phonon.show.warmingUp')}
													{/if}
												</p>
											</div>

											<div class="flex flex-wrap items-center gap-1.5" role="group" aria-label={$t('phonon.topic.label')}>
												<span class="mr-1 text-caption text-[var(--phonon-ink-muted)]">{$t('phonon.topic.label')}</span>
												{#each TOPIC_IDS as id, i (id)}
													<Hint label={TOPICS[id].label} keys={['⇧', String(i + 1)]}>
														{#snippet trigger({ props })}
															<Button
																{...props}
																size="xs"
																variant="ghost"
																aria-pressed={topic === id}
																onclick={() => chooseTopic(id)}
																class="rounded-none! border border-[var(--phonon-line)] font-mono {topic === id
																	? 'border-[var(--phonon-accent)]! bg-[var(--phonon-accent)]! text-[var(--phonon-accent-deep)]!'
																	: 'text-[var(--phonon-ink)]! hover:border-[var(--phonon-ink-muted)]! hover:bg-transparent!'}"
															>
																{TOPICS[id].label}
															</Button>
														{/snippet}
													</Hint>
												{/each}
											</div>
										</div>
									</div>

									<!-- The tube over all of it: scanlines, the refresh band, the glass. -->
									<div class="pointer-events-none absolute inset-0 z-20 overflow-hidden rounded-[inherit]" aria-hidden="true">
										<div class="arcade-scanlines absolute inset-0"></div>
										<div
											class="absolute inset-0 bg-[linear-gradient(to_bottom,transparent_0%,color-mix(in_srgb,var(--phonon-ink)_5%,transparent)_10%,transparent_20%)] motion-safe:animate-arcade-sweep motion-reduce:hidden"
										></div>
										<div class="arcade-glass absolute inset-0 rounded-[inherit]"></div>
										{#key flashes}
											<div class="absolute inset-0 bg-[var(--phonon-ink)] opacity-0 motion-safe:animate-arcade-flash"></div>
										{/key}
									</div>
								</div>
							</div>
						</div>

						<!-- The cabinet's buttons beside the tube. Under the tube on a phone. -->
						<div class="flex w-36 shrink-0 flex-col items-center gap-3 px-3 py-4 [transform-style:preserve-3d] max-md:w-full max-md:px-2 max-md:pt-1 max-md:pb-3">
							<div class="flex flex-1 flex-col items-center justify-center gap-3 max-md:flex-row max-md:items-start max-md:gap-2" role="group" aria-label={$t('phonon.stage.label')}>
								{#each STAGES as s (s.id)}
									{@render screenButton(s)}
								{/each}
							</div>
						</div>
					</div>

					<!-- The control panel, tilted toward the player: the keys the screen answers, as the
					     cabinet's own buttons; the master fader; START. 3D all the way down. -->
					<div
						class="relative flex h-[var(--deck)] origin-top items-center gap-7 bg-[var(--phonon-face)] px-8 [transform:rotateX(var(--tilt))] [transform-style:preserve-3d] max-md:h-auto max-md:justify-center max-md:gap-4 max-md:rounded-b-2xl max-md:px-3 max-md:py-4 max-md:[transform:none]"
					>
						<span class="arcade-dots arcade-shade-up pointer-events-none absolute inset-0" aria-hidden="true"></span>

						<div class="relative flex flex-1 flex-wrap items-start gap-x-5 gap-y-3 max-md:justify-center max-md:gap-x-4" role="group" aria-label={$t('phonon.cabinet.controls')}>
							{#each CONTROLS as c (c.label)}
								{@render control(c)}
							{/each}
						</div>

						<!-- The master fader beside START: Rex, the room and the cabinet's own sounds, all at
						     once. A phone has its own volume buttons. -->
						<div class="relative flex w-40 shrink-0 flex-col gap-1 [transform-style:preserve-3d] max-md:hidden">
							<span class="flex items-end justify-between px-[0.4375rem]" aria-hidden="true">
								{#each { length: 11 } as _, i (i)}
									<span class="w-px {i % 5 === 0 ? 'h-2 bg-[var(--phonon-ink-muted)]' : 'h-1 bg-[var(--phonon-ink-muted)] opacity-40'}"></span>
								{/each}
							</span>
							<Slider type="single" min={0} max={100} step={1} value={volume} onValueChange={setVolume} thumbLabel={$t('phonon.cabinet.volume')} class="arcade-fader h-7">
								{#snippet thumb()}
									<span data-face="cap-shadow"></span>
									<span data-face="cap-front"></span>
									<span data-face="cap-left"></span>
									<span data-face="cap-right"></span>
									<span data-face="cap-top"></span>
								{/snippet}
							</Slider>
							<span class="flex items-center justify-between">
								{@render komuna($t('phonon.cabinet.volume'), 'arcade-engraved text-[0.5625rem] text-[var(--phonon-ink-muted)]')}
								<!-- The level, on a little lit screen set into the deck. -->
								<span class="arcade-inlay relative overflow-hidden rounded-[3px] bg-[var(--phonon-screen)] px-1.5 py-0.5" aria-hidden="true">
									<span class="arcade-glow relative font-mono text-[0.6875rem] leading-none text-[var(--phonon-accent)] tabular-nums">{pad(volume, 3)}</span>
									<span class="arcade-scanlines pointer-events-none absolute inset-0"></span>
								</span>
							</span>
						</div>

						<!-- START: the runner's start button, and the cabinet's power. -->
						<Hint label={$t('phonon.keys.start')} keys={['↵']}>
							{#snippet trigger({ props })}
								<Button
									{...props}
									variant="ghost"
									onpointerdown={(event: PointerEvent) => {
										event.preventDefault();
										powerUp();
										press({ code: 'Enter', key: 'Enter', glyph: '' }, 'keydown');
									}}
									onpointerup={() => press({ code: 'Enter', key: 'Enter', glyph: '' }, 'keyup')}
									class="group relative h-auto! flex-col gap-1.5! rounded-none! p-0! font-mono hover:bg-transparent! max-md:hidden!"
								>
									<span class="flex size-14 items-center justify-center rounded-full bg-[var(--phonon-cabinet)] pb-1">
										<span
											class="arcade-key flex size-10 items-center justify-center rounded-full text-[var(--phonon-accent-deep)] transition-transform duration-75 [--cap:var(--phonon-accent)] group-active:translate-y-0.5 group-active:shadow-none {held.Enter
												? 'translate-y-0.5 shadow-none!'
												: '-translate-y-0.5'}"
										>
											{@render komuna($t('phonon.keys.start'), 'text-[0.5rem] font-[200] tracking-[0.1em]')}
										</span>
									</span>
								</Button>
							{/snippet}
						</Hint>
					</div>

					<!-- The kick panel, hanging off the deck's front edge: the links out, stuck on like
					     stickers, then the coin door and the maker's plate. -->
					<div
						class="relative flex flex-col gap-2 rounded-b-xl bg-[var(--phonon-bezel)] px-8 pt-2 pb-3 short:gap-0 short:pb-2 [margin-top:calc(var(--deck)*(cos(var(--tilt))-1))] [transform:translateZ(calc(var(--deck)*sin(var(--tilt))))] max-md:mt-3 max-md:rounded-2xl max-md:px-3 max-md:pt-4 max-md:pb-4 max-md:[transform:none]"
					>
						<span class="arcade-dots arcade-shade-up pointer-events-none absolute inset-0 rounded-b-xl" aria-hidden="true"></span>
						<!-- Two stickers up here, off to either side and at their own heights, the pair centred
						     over the third, down by the coin door. -->
						<nav aria-label={$t('phonon.cabinet.links')} class="relative flex flex-wrap items-center justify-center gap-x-20 gap-y-5 py-1.5 short:py-0 max-md:gap-x-10 max-md:py-3">
							{@render sticker(LINKS[1])}
							{@render sticker(LINKS[0])}
						</nav>

						<!-- Three columns, so the tag in the middle sits dead centre, under the two stickers
						     above, whatever the door and plaque measure. -->
						<div class="grid grid-cols-[1fr_auto_1fr] items-center gap-6 max-md:flex max-md:flex-col max-md:gap-4">
							<!-- The coin door: one lit slot. -->
							<div class="flex items-center gap-4 justify-self-start rounded-md bg-[var(--phonon-cabinet)] px-4 py-3 max-md:w-full max-md:justify-center">
								<Hint label={$t('phonon.arcade.insertCoin')} keys={['C']}>
									{#snippet trigger({ props })}
										<Button {...props} variant="ghost" onclick={insertCoin} aria-label={$t('phonon.arcade.insertCoin')} class="group h-auto! flex-col gap-1.5! rounded-none! p-0! hover:bg-transparent!">
											<span
												class="arcade-key flex h-11 w-8 -translate-y-0.5 items-center justify-center rounded-[3px] transition-transform [--cap:var(--phonon-accent)] group-active:translate-y-0.5 group-active:shadow-none"
											>
												<span class="h-6 w-1 rounded-full bg-[var(--phonon-bg)]"></span>
											</span>
										</Button>
									{/snippet}
								</Hint>
								<span class="flex flex-col gap-0.5 text-[0.625rem] tracking-[0.15em] uppercase">
									<span class="text-[var(--phonon-accent)]">{$t('phonon.arcade.insertCoin')}</span>
									<span class="text-[var(--phonon-ink-muted)] tabular-nums">{$t('phonon.arcade.coins', { credits: pad(credits, 2) })}</span>
								</span>
							</div>

							{@render sticker(LINKS[2])}

							<!-- The maker's plaque: engraved metal screwed to the cabinet, its gloss sliding as the
							     eye moves. -->
							<div class="arcade-plaque relative w-fit shrink-0 justify-self-end px-4 py-3 max-md:self-center" style:--glint-x={eye.x}>
								{#each ['top-1 left-1 [--turn:30deg]', 'top-1 right-1 [--turn:-55deg]', 'bottom-1 left-1 [--turn:80deg]', 'bottom-1 right-1 [--turn:10deg]'] as screw (screw)}
									<span class="arcade-screw {screw}" aria-hidden="true"></span>
								{/each}
								<div class="arcade-etched flex items-end gap-3 text-[0.625rem] leading-snug font-semibold tracking-[0.12em] uppercase">
									<p class="m-0 text-left whitespace-pre-line">{$t('phonon.cabinet.plate')}</p>
									<span class="tabular-nums">{PLAQUE_SERIAL}</span>
								</div>
							</div>
						</div>
					</div>
				</div>
			</div>
		</main>
	</div>
</div>
