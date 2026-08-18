<script lang="ts">
	import { typeColor } from '$lib/data/typeColors';

	let {
		name,
		type,
		pp = 0,
		maxPp,
		disabled = false,
		onclick
	}: {
		name?: string;
		type?: string;
		pp?: number;
		maxPp?: number;
		disabled?: boolean;
		onclick?: () => void;
	} = $props();

	const color = $derived(type ? typeColor(type) : '#475569');
	const isEmpty = $derived(!name);
</script>

{#if isEmpty}
	<div
		class="flex h-14.5 w-full items-center justify-center rounded-xl border border-dashed border-slate-800/60 bg-slate-950/30 font-mono text-xs font-semibold text-slate-700 select-none"
	>
		- EMPTY SLOT -
	</div>
{:else}
	<button
		class="group relative flex h-14.5 w-full cursor-pointer items-center justify-between rounded-xl border border-slate-800/80 bg-slate-950 px-4 transition-all duration-150 hover:enabled:border-cyan-400 hover:enabled:bg-slate-900 active:enabled:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-40"
		{disabled}
		{onclick}
	>
		<div class="flex min-w-0 items-center gap-3">
			{#if type}
				<span
					class="inline-flex min-w-16 shrink-0 justify-center rounded-md px-2 py-0.5 text-center font-mono text-[11px] font-black tracking-wider text-slate-950 uppercase shadow-sm"
					style="background-color: {color};"
				>
					{type}
				</span>
			{/if}

			<span
				class="truncate text-base font-extrabold tracking-wide text-white uppercase group-hover:text-cyan-300"
			>
				{name}
			</span>
		</div>

		<div class="shrink-0 pl-2 font-mono text-xs font-bold text-slate-400">
			<span class="text-slate-500">PP</span>
			<span class="text-white">{pp}</span>{#if maxPp}<span class="text-slate-600">/{maxPp}</span
				>{/if}
		</div>
	</button>
{/if}
