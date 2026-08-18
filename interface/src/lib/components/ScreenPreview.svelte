<script lang="ts">
	const POLL_INTERVAL_MS = 100;

	let src = $state('');
	let loaded = $state(false);

	$effect(() => {
		const screenUrl = `${window.location.protocol}//${window.location.host}/screen.png`;
		src = `${screenUrl}?t=${Date.now()}`;
		const id = setInterval(() => {
			src = `${screenUrl}?t=${Date.now()}`;
		}, POLL_INTERVAL_MS);
		return () => clearInterval(id);
	});
</script>

<div class="flex flex-col items-center gap-3 text-slate-600">
	{#if src}
		<img
			{src}
			alt="Live game screen"
			class="aspect-3/2 w-full max-w-5xl rounded-lg border border-slate-800 bg-black object-contain [image-rendering:pixelated]"
			class:hidden={!loaded}
			onload={() => (loaded = true)}
			onerror={() => (loaded = false)}
		/>
	{/if}
	{#if !loaded}
		<span>Waiting for a screenshot...</span>
	{/if}
</div>
