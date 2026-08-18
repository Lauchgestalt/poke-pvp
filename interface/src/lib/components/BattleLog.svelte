<script lang="ts">
	let { entries }: { entries: string[] } = $props();

	let logEl: HTMLDivElement | undefined;

	$effect(() => {
		if (logEl && entries.length) {
			logEl.scrollTo({ top: logEl.scrollHeight, behavior: 'smooth' });
		}
	});
</script>

<div class="rounded-2xl border border-slate-800/80 bg-slate-900/90 p-4 shadow-2xl backdrop-blur-sm">
	<div class="mb-3 flex items-center justify-between border-b border-slate-800/80 pb-2">
		<h2 class="text-xs font-black tracking-widest text-slate-400 uppercase">Battle Log</h2>
		<span class="font-mono text-[10px] font-bold text-slate-500">
			{entries.length} EVENTS
		</span>
	</div>

	<div
		bind:this={logEl}
		class="h-44 scrollbar-thin scrollbar-thumb-slate-800 scrollbar-track-transparent space-y-1.5 overflow-y-auto pr-2 font-mono text-xs"
	>
		{#if entries.length === 0}
			<div class="flex h-full items-center justify-center text-slate-600 italic">
				Waiting for battle actions...
			</div>
		{:else}
			{#each entries as entry, i (i)}
				<div class="flex items-start gap-2 leading-relaxed text-slate-300">
					<span class="shrink-0 font-bold text-cyan-500 select-none">&gt;</span>

					<span class="flex-1 wrap-break-word">
						{entry}
					</span>
				</div>
			{/each}
		{/if}
	</div>
</div>

<style>
	div::-webkit-scrollbar {
		width: 4px;
	}
	div::-webkit-scrollbar-track {
		background: transparent;
	}
	div::-webkit-scrollbar-thumb {
		background: #334155;
		border-radius: 9999px;
	}
	div::-webkit-scrollbar-thumb:hover {
		background: #475569;
	}
</style>
