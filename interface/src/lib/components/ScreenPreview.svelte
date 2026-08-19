<script lang="ts">
    import { streamSettings } from '$lib/streamSettings.svelte';
    import { battle } from '$lib/battleConnection.svelte';
</script>

<div class="flex flex-col items-center gap-3 text-slate-600">
    {#if !streamSettings.enabled}
        <span class="text-center">
            Screenshot streaming is off.<br />
            <span class="text-xs">Turn it on in Settings, or just screen-share the game instead.</span>
        </span>
    {:else if battle.battleState}
        <span>Battle in progress</span>
    {:else if battle.latestFrameUrl}
        <div class="relative w-full max-w-5xl overflow-hidden rounded-xl border-4 border-slate-900 bg-black shadow-2xl">
            
            <div class="pointer-events-none absolute inset-0 z-10 bg-[linear-gradient(transparent_50%,rgba(0,0,0,0.3)_50%)] bg-size-[100%_4px] shadow-[inset_0_0_60px_rgba(0,0,0,0.8)]"></div>
            
            <div class="pointer-events-none absolute left-4 top-4 z-20 flex items-center gap-2 rounded border border-white/10 bg-black/50 px-2.5 py-1 text-xs font-bold uppercase tracking-widest text-slate-300 backdrop-blur-sm">
                <span class="h-2 w-2 animate-pulse rounded-full bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.8)]"></span>
                {battle.playerName || "Player 1"} Feed
            </div>
            
            <img
                src={battle.latestFrameUrl}
                alt="Live game screen"
                class="pointer-events-none aspect-3/2 w-full object-contain opacity-90 grayscale-15% [image-rendering:pixelated]"
            />
        </div>
    {:else}
        <span class="flex items-center gap-2 animate-pulse">
            Waiting for visual signal...
        </span>
    {/if}
</div>