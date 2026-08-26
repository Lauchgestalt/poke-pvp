<script lang="ts">
	import { SPECIES_NAMES } from '$lib/data/speciesNames';
	import PokemonSprite from './PokemonSprite.svelte';
	import type { RevealedMon } from '$lib/battleConnection.svelte';

	let { mons, label }: { mons: RevealedMon[]; label: string } = $props();

	const speciesName = (id: number) => SPECIES_NAMES[id] ?? `Species #${id}`;
</script>

{#if mons.length > 0}
	<div class="rounded-xl border border-slate-800/80 bg-slate-900/60 p-3">
		<div class="mb-2 text-[10px] font-black tracking-widest text-slate-500 uppercase">
			{label} -- {mons.filter((m) => !m.fainted).length}/{mons.length} still standing
		</div>
		<div class="flex flex-wrap gap-2">
			{#each mons as mon (mon.species)}
				<div
					class="flex items-center gap-1.5 rounded-lg border px-1.5 py-1 {mon.fainted
						? 'border-red-900/40 bg-red-950/20 opacity-60 grayscale'
						: 'border-slate-800 bg-slate-950/60'}"
					title={mon.nickname && mon.nickname.trim() ? mon.nickname : speciesName(mon.species)}
				>
					<PokemonSprite species={mon.species} alt={speciesName(mon.species)} class="h-7 w-7" />
					{#if mon.fainted}
						<span class="pr-0.5 text-xs font-black text-red-500">✕</span>
					{/if}
				</div>
			{/each}
		</div>
	</div>
{/if}
