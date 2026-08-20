<script lang="ts">
	import { SPECIES_NAMES } from '$lib/data/speciesNames';
	import PokemonSprite from './PokemonSprite.svelte';
	import type { PartyMon } from '$lib/types';

	let {
		party,
		activeSlot,
		disabled,
		onSwitch
	}: {
		party: PartyMon[];
		activeSlot: number;
		disabled: boolean;
		onSwitch: (slot: number) => void;
	} = $props();

	const speciesName = (id: number) => SPECIES_NAMES[id] ?? `Species #${id}`;
	const displayName = (mon: PartyMon) =>
		mon.nickname && mon.nickname.trim() !== '' ? mon.nickname : speciesName(mon.species);
</script>

<div
	class="w-80 shrink-0 rounded-2xl border border-slate-800/80 bg-slate-900/90 p-4 shadow-2xl backdrop-blur-sm"
>
	<div class="mb-3 flex items-center justify-between border-b border-slate-800/80 pb-2.5">
		<h2 class="text-xs font-black tracking-widest text-slate-400 uppercase">Team Switch</h2>
		<span class="flex items-center gap-1.5 font-mono text-[11px] font-bold text-emerald-400">
			<span class="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400"></span>
			{party.filter((m) => m.hp > 0).length}/{party.length} ALIVE
		</span>
	</div>

	{#if party.length === 0}
		<div class="py-8 text-center font-mono text-xs text-slate-600">(no party data synced)</div>
	{:else}
		<div class="space-y-2">
			{#each party as mon (mon.partySlot)}
				{@const isActive = mon.partySlot === activeSlot}
				{@const fainted = mon.hp <= 0}
				{@const pct = mon.maxHp ? Math.round((mon.hp / mon.maxHp) * 100) : 0}
				{@const hpBarClass =
					pct <= 20 ? 'bg-red-500' : pct <= 50 ? 'bg-amber-400' : 'bg-emerald-500'}

				<button
					class="group relative flex w-full cursor-pointer items-center gap-3 rounded-xl border p-2.5 text-left transition-all duration-150 disabled:cursor-not-allowed disabled:opacity-50 {isActive
						? 'border-emerald-500/60 bg-emerald-950/30 shadow-[0_0_12px_rgba(16,185,129,0.15)]'
						: fainted
							? 'border-red-900/30 bg-slate-950/40 grayscale'
							: 'border-slate-800/90 bg-slate-950/60 hover:border-slate-700 hover:bg-slate-800/50'}"
					disabled={disabled || isActive || fainted}
					onclick={() => onSwitch(mon.partySlot)}
				>
					<div
						class="relative flex h-11 w-11 shrink-0 items-center justify-center rounded-lg border border-slate-800 bg-slate-900/80"
					>
						<PokemonSprite
							species={mon.species}
							alt={speciesName(mon.species)}
							class="h-10 w-10 object-contain transition-transform group-hover:scale-110"
						/>
					</div>

					<div class="min-w-0 flex-1">
						<div class="flex items-center justify-between gap-1.5">
							<span class="truncate text-sm font-extrabold tracking-tight text-white">
								{displayName(mon)}
							</span>

							{#if isActive}
								<span
									class="shrink-0 rounded border border-emerald-500/30 bg-emerald-500/20 px-1.5 py-0.5 font-mono text-[9px] font-black tracking-wider text-emerald-400"
								>
									ACTIVE
								</span>
							{:else if fainted}
								<span
									class="shrink-0 rounded border border-red-800/40 bg-red-950/60 px-1.5 py-0.5 font-mono text-[9px] font-bold tracking-wider text-red-400"
								>
									FAINTED
								</span>
							{/if}
						</div>

						<div
							class="mt-1.5 h-2 w-full overflow-hidden rounded-full border border-slate-800/80 bg-slate-950 p-0.5"
						>
							<div
								class="h-full rounded-full transition-all duration-300 {hpBarClass}"
								style="width: {pct}%"
							></div>
						</div>

						<div
							class="mt-1 flex items-center justify-between font-mono text-[10px] text-slate-400"
						>
							<span>HP</span>
							<span class="font-bold text-slate-300">{mon.hp}/{mon.maxHp}</span>
						</div>
					</div>
				</button>
			{/each}
		</div>
	{/if}
</div>
