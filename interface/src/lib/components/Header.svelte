<script lang="ts">
	import { battle } from '$lib/battleConnection.svelte';

	let { activeTab }: { activeTab: 'battle' | 'stream' } = $props();

	let nameInput = $state(battle.myName ?? '');

	function submitName() {
		battle.setMyName(nameInput);
	}
</script>

<header class="flex items-center justify-between border-b border-slate-800 px-6 py-4">
	<h1 class="text-xs font-bold tracking-widest text-slate-500 uppercase">
		{activeTab === 'stream' ? 'Stream' : 'Battle'}
	</h1>
	<div class="flex items-center gap-4 text-xs">
		<form class="flex items-center gap-1.5" onsubmit={(e) => (e.preventDefault(), submitName())}>
			<label for="player2-name" class="text-slate-500">Your trainer name:</label>
			<input
				id="player2-name"
				bind:value={nameInput}
				maxlength="11"
				placeholder="e.g. Ash"
				class="w-24 rounded border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200 placeholder-slate-600 focus:border-cyan-500 focus:outline-none"
			/>
			<button
				type="submit"
				class="rounded border border-slate-700 px-2 py-1 font-semibold text-slate-300 hover:border-cyan-500 hover:text-cyan-400"
			>
				Set
			</button>
			{#if battle.myName}
				<span class="text-emerald-400">saved</span>
			{/if}
		</form>
		<span
			class="flex items-center gap-1.5 rounded-full border border-slate-700 px-3 py-1 font-semibold"
		>
			<span class="h-1.5 w-1.5 rounded-full {battle.connected ? 'bg-green-400' : 'bg-red-400'}"
			></span>
			{battle.connected ? 'ONLINE' : 'OFFLINE'}
		</span>
	</div>
</header>
