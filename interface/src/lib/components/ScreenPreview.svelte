<script lang="ts">
	const SCREEN_URL = 'http://127.0.0.1:8767/screen.png';
	const POLL_INTERVAL_MS = 100;

	let src = $state(`${SCREEN_URL}?t=0`);
	let loaded = $state(false);

	$effect(() => {
		const id = setInterval(() => {
			src = `${SCREEN_URL}?t=${Date.now()}`;
		}, POLL_INTERVAL_MS);
		return () => clearInterval(id);
	});
</script>

<div class="flex flex-col items-center gap-3 text-slate-600">
	<img
		{src}
		alt="Live game screen"
		class="aspect-3/2 w-full max-w-5xl rounded-lg border border-slate-800 bg-black object-contain [image-rendering:pixelated]"
		class:hidden={!loaded}
		onload={() => (loaded = true)}
		onerror={() => (loaded = false)}
	/>
	{#if !loaded}
		<span>Waiting for a screenshot...</span>
	{/if}
</div>
