<script lang="ts">
	import { streamSettings } from '$lib/streamSettings.svelte';
	import { battle } from '$lib/battleConnection.svelte';

	const POLL_INTERVAL_MS = 100;

	let src = $state('');
	let loaded = $state(false);
	let screenUrl = '';
	let active = false;
	let timer: ReturnType<typeof setTimeout> | undefined;

	function requestFrame() {
		if (!active) return;
		src = `${screenUrl}?t=${Date.now()}`;
	}

	function scheduleNext() {
		if (!active) return;
		clearTimeout(timer);
		timer = setTimeout(requestFrame, POLL_INTERVAL_MS);
	}

	function handleLoad() {
		loaded = true;
		scheduleNext();
	}

	function handleError() {
		loaded = false;
		scheduleNext();
	}

	$effect(() => {
		if (!streamSettings.enabled || battle.battleState) return;
		screenUrl = `${window.location.protocol}//${window.location.host}/screen.png`;
		active = true;
		requestFrame();
		return () => {
			active = false;
			clearTimeout(timer);
			loaded = false;
			src = '';
		};
	});
</script>

<div class="flex flex-col items-center gap-3 text-slate-600">
	{#if !streamSettings.enabled}
		<span class="text-center">
			Screenshot streaming is off.<br />
			<span class="text-xs">Turn it on in Settings, or just screen-share the game instead.</span>
		</span>
	{:else if battle.battleState}
		<span>Battle in progress</span>
	{:else}
		{#if src}
			<img
				{src}
				alt="Live game screen"
				class="aspect-3/2 w-full max-w-5xl rounded-lg border border-slate-800 bg-black object-contain [image-rendering:pixelated]"
				class:hidden={!loaded}
				onload={handleLoad}
				onerror={handleError}
			/>
		{/if}
		{#if !loaded}
			<span>Waiting for a screenshot...</span>
		{/if}
	{/if}
</div>
