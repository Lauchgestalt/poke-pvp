<script lang="ts">
	import { Swords, MonitorPlay, CircleDot } from '@lucide/svelte';

	let { activeTab, onSelect }: { activeTab: 'battle' | 'stream'; onSelect: (tab: 'battle' | 'stream') => void } =
		$props();

	const tabClass = (tab: 'battle' | 'stream') =>
		`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left ${
			activeTab === tab ? 'bg-cyan-500/10 text-cyan-400' : 'text-slate-400 hover:text-slate-200'
		}`;
</script>

<aside class="hidden w-56 shrink-0 flex-col border-r border-slate-800 bg-slate-950/80 p-4 md:flex">
	<div class="mb-8 flex items-center gap-2 px-2">
		<span class="text-2xl"><CircleDot /></span>
		<span class="text-lg font-black tracking-wide">POKé<span class="text-cyan-400">PVP</span></span>
	</div>
	<nav class="space-y-1 text-sm font-semibold">
		<button class={tabClass('battle')} onclick={() => onSelect('battle')}>
			<Swords /> Battle
		</button>
		<button class={tabClass('stream')} onclick={() => onSelect('stream')}>
			<MonitorPlay /> Stream
		</button>
	</nav>
</aside>
