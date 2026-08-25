<script lang="ts">
	import { onMount } from 'svelte';
	import { battle } from '$lib/battleConnection.svelte';
	import { streamSettings } from '$lib/streamSettings.svelte';
	import { MOVE_NAMES } from '$lib/data/moveNames';
	import { MOVE_TYPES } from '$lib/data/moveTypes';
	import { ITEM_NAMES } from '$lib/data/itemNames';
	import { SPECIES_NAMES } from '$lib/data/speciesNames';
	import Sidebar from '$lib/components/Sidebar.svelte';
	import Header from '$lib/components/Header.svelte';
	import MonCard from '$lib/components/MonCard.svelte';
	import MoveButton from '$lib/components/MoveButton.svelte';
	import ItemButton from '$lib/components/ItemButton.svelte';
	import PartySwitchList from '$lib/components/PartySwitchList.svelte';
	import BattleLog from '$lib/components/BattleLog.svelte';
	import ScreenPreview from '$lib/components/ScreenPreview.svelte';
	import PokemonSprite from '$lib/components/PokemonSprite.svelte';
	import type { ActiveMon, BattleState } from '$lib/types';

	let activeTab = $state<'battle' | 'stream'>(streamSettings.enabled ? 'stream' : 'battle');
	let wasInBattle = false;

	let target1 = $state<0 | 2>(0);
	let target3 = $state<0 | 2>(0);

	let switchTab = $state<1 | 3>(1);

	const speciesName = (id: number) => SPECIES_NAMES[id] ?? `Species #${id}`;

	$effect(() => {
		const inBattle = battle.battleState !== null;
		if (inBattle && !wasInBattle) {
			activeTab = 'battle';
		} else if (!inBattle && wasInBattle && streamSettings.enabled) {
			activeTab = 'stream';
		}
		wasInBattle = inBattle;
	});

	onMount(() => {
		battle.connect();
	});
</script>

<svelte:head>
	<title>PokePVP</title>
</svelte:head>

{#snippet targetPicker(
	mon: ActiveMon,
	mon2: ActiveMon,
	target: 0 | 2,
	onSelect: (t: 0 | 2) => void
)}
	<div class="mb-3 flex gap-2">
		{#each [mon, mon2] as m, i (i)}
			{@const t = i === 0 ? 0 : 2}
			<button
				type="button"
				class="flex flex-1 cursor-pointer items-center gap-2 rounded-lg border px-2 py-1.5 text-left transition-colors {t ===
				target
					? 'border-emerald-500/60 bg-emerald-950/40'
					: 'border-slate-800 bg-slate-950/60 hover:border-slate-700'}"
				onclick={() => onSelect(t)}
			>
				<PokemonSprite species={m.species} alt={speciesName(m.species)} class="h-8 w-8 shrink-0" />
				<span class="min-w-0 flex-1 font-mono text-xs">
					<span class="block truncate font-bold {t === target ? 'text-emerald-300' : 'text-white'}"
						>{speciesName(m.species)}</span
					>
					<span class="text-slate-500">{m.hp}/{m.maxHp}</span>
				</span>
			</button>
		{/each}
	</div>
{/snippet}

{#snippet actionGrid(
	state: BattleState,
	battlerSlot: 1 | 3,
	submitted: boolean,
	target: 0 | 2 | undefined,
	locked: boolean
)}
	{#if locked}
		<div class="mb-2 text-center text-xs text-slate-500">
			Waiting for the other Pokemon's move to be chosen first...
		</div>
	{/if}
	{#if state.mustSwitch}
		<div
			class="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-center text-sm font-semibold text-amber-300"
		>
			Your Pokemon fainted! Choose a replacement from the party list.
		</div>
	{:else}
		<div class="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
			{#each Array(4) as _, i (i)}
				{@const moveId = state.enemyMoveIds[i]}
				{@const pp = state.pp[i] ?? 0}
				{@const hasMove = Boolean(moveId && moveId > 0)}

				<MoveButton
					name={hasMove ? (MOVE_NAMES[moveId] ?? `Move #${moveId}`) : undefined}
					type={hasMove ? (MOVE_TYPES[moveId] ?? 'Normal') : undefined}
					{pp}
					disabled={!hasMove || pp <= 0 || submitted || locked || battle.role !== 'controller'}
					onclick={() => battle.chooseMove(i, battlerSlot, target)}
				/>
			{/each}
		</div>

		{#if state.availableItems.length > 0}
			<div class="mt-4 grid grid-cols-1 gap-2.5 sm:grid-cols-2">
				{#each state.availableItems as { itemId, count } (itemId)}
					<ItemButton
						name={ITEM_NAMES[itemId] ?? `Item #${itemId}`}
						{count}
						disabled={submitted || locked || battle.role !== 'controller'}
						onclick={() => battle.chooseItem(itemId, battlerSlot)}
					/>
				{/each}
			</div>
		{/if}
	{/if}
{/snippet}

<div class="flex min-h-screen bg-[#0a0e17] text-white">
	<Sidebar {activeTab} onSelect={(tab) => (activeTab = tab)} />

	<div class="flex flex-1 flex-col">
		<Header {activeTab} />

		<main class="flex flex-1 flex-wrap gap-6 p-6">
			<div class="min-w-0 flex-1">
				{#if activeTab === 'stream'}
					<ScreenPreview />
				{:else if battle.battleState}
					{@const state = battle.battleState}
					{#if state.playerActive2}
						{@const playerActive2 = state.playerActive2}
						<div class="mx-auto mb-6 grid max-w-5xl grid-cols-1 gap-4 sm:grid-cols-2">
							<MonCard
								label={battle.playerName ?? 'Player 1'}
								mon={state.playerActive}
								accent="red"
								playerId="1"
							/>
							<MonCard
								label={battle.playerName ?? 'Player 1'}
								mon={playerActive2}
								accent="red"
								playerId="1"
							/>
						</div>

						<div class="mx-auto grid max-w-5xl grid-cols-1 gap-6 lg:grid-cols-2">
							<div>
								<MonCard
									label={battle.myName ?? 'Player 2'}
									mon={state.enemyActive}
									accent="blue"
									playerId="2"
								/>
								<div class="mt-3">
									{@render targetPicker(
										state.playerActive,
										playerActive2,
										target1,
										(t) => (target1 = t)
									)}
									{@render actionGrid(state, 1, battle.submitted, target1, false)}
								</div>
							</div>
							{#if battle.battleState3}
								{@const state3 = battle.battleState3}
								<div>
									<MonCard
										label={`${battle.myName ?? 'Player 2'} (2)`}
										mon={state3.enemyActive}
										accent="blue"
										playerId="2"
									/>
									<div class="mt-3">
										{@render targetPicker(
											state3.playerActive,
											state3.playerActive2 ?? state3.playerActive,
											target3,
											(t) => (target3 = t)
										)}
										{@render actionGrid(state3, 3, battle.submitted3, target3, !battle.submitted)}
									</div>
								</div>
							{/if}
						</div>
					{:else}
						<div class="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
							<MonCard
								label={battle.playerName ?? 'Player 1'}
								mon={state.playerActive}
								accent="red"
								playerId="1"
							/>
							<MonCard
								label={battle.myName ?? 'Player 2'}
								mon={state.enemyActive}
								accent="blue"
								playerId="2"
							/>
						</div>

						<div class="mx-auto max-w-4xl">
							{@render actionGrid(state, 1, battle.submitted, undefined, false)}
						</div>
					{/if}

					<div class="mx-auto mt-15 max-w-5xl">
						<BattleLog entries={battle.log} />
					</div>
				{:else}
					<div class="flex h-64 items-center justify-center text-slate-600">No active battle</div>
				{/if}
			</div>

			{#if activeTab === 'battle' && battle.battleState}
				{#if battle.battleState3}
					<div class="flex flex-col gap-3">
						<div class="flex gap-2 font-mono text-xs font-bold">
							<button
								type="button"
								class="flex-1 cursor-pointer rounded-lg border px-2 py-1.5 transition-colors {switchTab ===
								1
									? 'border-emerald-500/60 bg-emerald-950/40 text-emerald-300'
									: 'border-slate-800 bg-slate-950/60 text-slate-400 hover:border-slate-700'}"
								onclick={() => (switchTab = 1)}
							>
								{speciesName(battle.battleState.enemyActive.species)}'s team
							</button>
							<button
								type="button"
								class="flex-1 cursor-pointer rounded-lg border px-2 py-1.5 transition-colors {switchTab ===
								3
									? 'border-emerald-500/60 bg-emerald-950/40 text-emerald-300'
									: 'border-slate-800 bg-slate-950/60 text-slate-400 hover:border-slate-700'}"
								onclick={() => (switchTab = 3)}
							>
								{speciesName(battle.battleState3.enemyActive.species)}'s team
							</button>
						</div>
						{#if switchTab === 1}
							{@const state = battle.battleState}
							<PartySwitchList
								party={state.enemyParty}
								activeSlot={state.enemyActivePartySlot}
								disabled={battle.submitted || battle.role !== 'controller'}
								onSwitch={(slot) => battle.chooseSwitch(slot)}
							/>
						{:else}
							{@const state = battle.battleState3}
							<PartySwitchList
								party={state.enemyParty}
								activeSlot={state.enemyActivePartySlot}
								disabled={battle.submitted3 || battle.role !== 'controller'}
								onSwitch={(slot) => battle.chooseSwitch(slot, 3)}
							/>
						{/if}
					</div>
				{:else}
					{@const state = battle.battleState}
					<PartySwitchList
						party={state.enemyParty}
						activeSlot={state.enemyActivePartySlot}
						disabled={battle.submitted || battle.role !== 'controller'}
						onSwitch={(slot) => battle.chooseSwitch(slot)}
					/>
				{/if}
			{/if}
		</main>
	</div>
</div>
