<script lang="ts">
	let {
		name,
		count,
		disabled = false,
		onclick
	}: {
		name: string;
		count: number;
		disabled?: boolean;
		onclick?: () => void;
	} = $props();
</script>

<button
	class="group relative flex h-14.5 w-full cursor-pointer items-center justify-between gap-3 rounded-xl border border-slate-800/80 bg-slate-950 px-4 transition-all duration-150 hover:enabled:border-emerald-400 hover:enabled:bg-slate-900 active:enabled:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-40"
	{disabled}
	{onclick}
>
	<div class="flex min-w-0 items-center gap-3">
		<span>
			<img
				src="https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/{name.toLowerCase()}.png"
				alt={name}
				class="h-8 w-8 rounded-md border border-slate-800/80 bg-slate-900/80 object-contain"
			/>
		</span>
		<span
			class="truncate text-base font-extrabold tracking-wide text-white uppercase group-hover:text-emerald-300"
		>
			{name}
		</span>
	</div>

	<div class="shrink-0 pl-2 font-mono text-xs font-bold text-slate-400">
		<span class="text-slate-500">x</span><span class="text-white">{count}</span>
	</div>
</button>
