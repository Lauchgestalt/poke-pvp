<script lang="ts">
	import { onMount } from 'svelte';
	import { battle } from '$lib/battleConnection.svelte';
	import { streamSettings } from '$lib/streamSettings.svelte';
	import { MOVE_NAMES } from '$lib/data/moveNames';
	import { MOVE_TYPES } from '$lib/data/moveTypes';
	import { ITEM_NAMES } from '$lib/data/itemNames';
	import Sidebar from '$lib/components/Sidebar.svelte';
	import Header from '$lib/components/Header.svelte';
	import MonCard from '$lib/components/MonCard.svelte';
	import MoveButton from '$lib/components/MoveButton.svelte';
	import ItemButton from '$lib/components/ItemButton.svelte';
	import PartySwitchList from '$lib/components/PartySwitchList.svelte';
	import BattleLog from '$lib/components/BattleLog.svelte';
	import ScreenPreview from '$lib/components/ScreenPreview.svelte';

	let activeTab = $state<'battle' | 'stream'>(streamSettings.enabled ? 'stream' : 'battle');
	let wasInBattle = false;

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

					{#if state.mustSwitch}
						<div
							class="mx-auto mb-6 max-w-4xl rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-center text-sm font-semibold text-amber-300"
						>
							Your Pokemon fainted! Choose a replacement from the party list.
						</div>
					{:else}
						<div class="mx-auto mb-6 grid max-w-4xl grid-cols-1 gap-3 sm:grid-cols-2">
							<h2
								class="col-span-2 mb-3 text-xs font-bold tracking-widest text-slate-500 uppercase"
							>
								Choose a move
							</h2>
							{#each Array(4) as _, i (i)}
								{@const moveId = state.enemyMoveIds[i]}
								{@const pp = state.pp[i] ?? 0}
								{@const hasMove = Boolean(moveId && moveId > 0)}

								<MoveButton
									name={hasMove ? (MOVE_NAMES[moveId] ?? `Move #${moveId}`) : undefined}
									type={hasMove ? (MOVE_TYPES[moveId] ?? 'Normal') : undefined}
									{pp}
									disabled={!hasMove || pp <= 0 || battle.submitted || battle.role !== 'controller'}
									onclick={() => battle.chooseMove(i)}
								/>
							{/each}
						</div>

						{#if state.availableItems.length > 0}
							<div class="mx-auto mb-6 grid max-w-4xl grid-cols-1 gap-3 sm:grid-cols-2">
								<h2
									class="col-span-2 mb-3 text-xs font-bold tracking-widest text-slate-500 uppercase"
								>
									Use an item
								</h2>
								{#each state.availableItems as { itemId, count } (itemId)}
									<ItemButton
										name={ITEM_NAMES[itemId] ?? `Item #${itemId}`}
										{count}
										disabled={battle.submitted || battle.role !== 'controller'}
										onclick={() => battle.chooseItem(itemId)}
									/>
								{/each}
							</div>
						{/if}
					{/if}

					<div class="mx-auto mt-15 max-w-4xl">
						<BattleLog entries={battle.log} />
					</div>
				{:else}
					<div class="flex h-64 items-center justify-center text-slate-600">No active battle</div>
				{/if}
			</div>

			{#if activeTab === 'battle' && battle.battleState}
				{@const state = battle.battleState}
				<PartySwitchList
					party={state.enemyParty}
					activeSlot={state.enemyActivePartySlot}
					disabled={battle.submitted || battle.role !== 'controller'}
					onSwitch={(slot) => battle.chooseSwitch(slot)}
				/>
			{/if}
		</main>
	</div>
</div>
