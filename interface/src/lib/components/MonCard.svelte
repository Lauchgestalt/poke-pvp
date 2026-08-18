<script lang="ts">
	import { SPECIES_NAMES } from '$lib/data/speciesNames';
	import { SPECIES_TYPES } from '$lib/data/speciesTypes';
	import { typeColor } from '$lib/data/typeColors';
	import { spriteUrl } from '$lib/data/spriteUrl';
	import type { ActiveMon } from '$lib/types';

	let {
		label,
		mon,
		accent,
		playerId
	}: {
		label: string;
		mon: ActiveMon;
		accent: 'red' | 'blue';
		playerId: '1' | '2';
	} = $props();

	const speciesName = (id: number) => SPECIES_NAMES[id] ?? `Species #${id}`;
	const types = $derived(SPECIES_TYPES[mon.species] ?? ['Normal']);
	const pct = $derived(mon.maxHp ? Math.round((mon.hp / mon.maxHp) * 100) : 0);

	const hpBarClass = $derived(
		pct <= 20 ? 'bg-red-500' : pct <= 50 ? 'bg-amber-400' : 'bg-emerald-500'
	);
	
	const cardBorder = $derived(
		accent === 'red' ? 'border-red-900/40 bg-slate-900/90' : 'border-blue-900/40 bg-slate-900/90'
	);

	const headerText = $derived(
		accent === 'red' ? 'text-red-500' : 'text-blue-400'
	);

	const platformBg = $derived(
		accent === 'red' ? 'bg-slate-800/80 border-slate-700/50' : 'bg-purple-950/60 border-purple-800/40'
	);

	const isP1 = $derived(playerId === '1');
	const spriteOrderClass = $derived(isP1 ? 'order-first' : 'order-last');
	const statsOrderClass = $derived(isP1 ? 'order-last' : 'order-first');
	const spriteFlip = $derived(isP1 ? 'scale-x-[-1]' : '');
	
	const animDelay = $derived(isP1 ? '0s' : '-1.5s');
</script>

<div class="relative overflow-hidden rounded-2xl border {cardBorder} p-5 shadow-2xl backdrop-blur-sm">
	
	<div class="mb-4 flex items-center justify-between border-b border-slate-800/80 pb-2">
		<span class="text-sm font-black tracking-wider uppercase {headerText}">
			{label}
		</span>
	</div>

	<div class="grid grid-cols-12 gap-4 items-center">
		
		<div class="col-span-5 flex flex-col items-center justify-center relative {spriteOrderClass}">
			<div class="relative flex items-center justify-center w-full aspect-square max-w-35">
				<div class="absolute bottom-2 w-full h-10 rounded-[50%] border {platformBg} shadow-inner"></div>
				
				{#if spriteUrl(mon.species)}
					<img
						src={spriteUrl(mon.species)}
						alt={speciesName(mon.species)}
						class="relative z-10 h-28 w-28 object-contain animate-float [image-rendering:pixelated] drop-shadow-[0_10px_8px_rgba(0,0,0,0.5)] {spriteFlip}"
						style="animation-delay: {animDelay};"
						loading="lazy"
					/>
				{/if}
			</div>
		</div>

		<div class="col-span-7 flex flex-col justify-center space-y-3 font-sans {statsOrderClass}">
			<div>
				<div class="flex items-baseline space-x-2">
					<h3 class="text-2xl font-extrabold tracking-tight text-white">
						{speciesName(mon.species)}
					</h3>
					<span class="text-sm font-semibold text-slate-400">
						Lv. {mon.level}
					</span>
				</div>
			</div>

			<div class="space-y-1">
				<div class="flex justify-between font-mono text-xs font-bold text-slate-300">
					<span>HP: {mon.hp}/{mon.maxHp}</span>
				</div>
				<div class="h-3 w-full overflow-hidden rounded-full bg-slate-950 p-0.5 border border-slate-800">
					<div
						class="h-full rounded-full transition-all duration-300 {hpBarClass}"
						style="width: {pct}%"
					></div>
				</div>
			</div>

			<div class="flex items-center gap-1.5 pt-1">
				<span class="mr-1 text-xs font-medium text-slate-400">Type:</span>
				{#each types as t (t)}
					<span
						class="rounded-md px-2.5 py-0.5 text-xs font-bold text-white shadow-sm tracking-wide"
						style="background-color: {typeColor(t)}"
					>
						{t}
					</span>
				{/each}
			</div>
		</div>

	</div>
</div>

<style>
	@keyframes float-idle {
		0%, 100% {
			transform: translateY(0px) scale(1);
		}
		50% {
			transform: translateY(-10px) scale(1.05);
		}
	}

	.animate-float {
		animation: float-idle 2s ease-in-out infinite;
	}
</style>