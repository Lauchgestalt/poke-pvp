<script lang="ts">
	import type { Snippet } from 'svelte';

	let { children, tooltip }: { children: Snippet; tooltip: Snippet } = $props();
</script>

<div class="group/tip relative">
	{@render children()}
	<div
		class="pointer-events-none absolute bottom-full left-1/2 z-30 mb-2 w-max max-w-64 -translate-x-1/2 scale-95 rounded-lg border border-slate-700 bg-slate-950 p-2.5 opacity-0 shadow-2xl transition-all duration-100 group-hover/tip:scale-100 group-hover/tip:opacity-100"
	>
		{@render tooltip()}
	</div>
</div>
