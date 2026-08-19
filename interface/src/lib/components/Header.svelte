<script lang="ts">
	import { battle } from '$lib/battleConnection.svelte';
	import { spriteSettings } from '$lib/spriteSettings.svelte';
	import { streamSettings, MIN_STREAM_FPS, MAX_STREAM_FPS } from '$lib/streamSettings.svelte';
	import { SPRITE_STYLES } from '$lib/data/spriteStyles';
	import { Settings } from '@lucide/svelte';

	let { activeTab }: { activeTab: 'battle' | 'stream' } = $props();

	let nameInput = $state(battle.myName ?? '');
	let tokenInput = $state('');
	let settingsOpen = $state(false);
	let buttonEl: HTMLButtonElement | undefined = $state();
	let panelEl: HTMLDivElement | undefined = $state();

	function submitName() {
		battle.setMyName(nameInput);
	}

	function submitToken() {
		battle.setAuthToken(tokenInput);
		tokenInput = '';
	}

	const spriteGroups = Array.from(new Set(SPRITE_STYLES.map((s) => s.group)));

	$effect(() => {
		if (!settingsOpen) return;
		function handleClickOutside(e: MouseEvent) {
			const target = e.target as Node;
			if (panelEl?.contains(target) || buttonEl?.contains(target)) return;
			settingsOpen = false;
		}
		window.addEventListener('click', handleClickOutside);
		return () => window.removeEventListener('click', handleClickOutside);
	});
</script>

<header class="relative flex items-center justify-between border-b border-slate-800 px-6 py-4">
	<h1 class="text-xs font-bold tracking-widest text-slate-500 uppercase">
		{activeTab === 'stream' ? 'Stream' : 'Battle'}
	</h1>
	<div class="flex items-center gap-4 text-xs">
		<button
			bind:this={buttonEl}
			type="button"
			aria-label="Settings"
			onclick={() => (settingsOpen = !settingsOpen)}
			class="flex items-center gap-1.5 rounded border px-2 py-1.5 {settingsOpen
				? 'border-cyan-500 text-cyan-400'
				: 'border-slate-700 text-slate-300 hover:border-cyan-500 hover:text-cyan-400'}"
		>
			<Settings size={16} />
		</button>
		<span
			class="flex items-center gap-1.5 rounded-full border border-slate-700 px-3 py-1 font-semibold"
		>
			<span class="h-1.5 w-1.5 rounded-full {battle.connected ? 'bg-green-400' : 'bg-red-400'}"
			></span>
			{battle.connected ? 'ONLINE' : 'OFFLINE'}
		</span>
	</div>

	{#if settingsOpen}
		<div
			bind:this={panelEl}
			class="absolute top-full right-6 z-20 mt-2 w-72 space-y-4 rounded-xl border border-slate-800 bg-slate-950 p-4 shadow-2xl"
		>
			<div>
				<label for="controller-token" class="mb-1 block text-slate-500">Controller token</label>
				<form
					class="flex items-center gap-1.5"
					onsubmit={(e) => (e.preventDefault(), submitToken())}
				>
					<input
						id="controller-token"
						bind:value={tokenInput}
						placeholder="paste the token Player 1 sent you"
						class="w-full rounded border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200 placeholder-slate-600 focus:border-cyan-500 focus:outline-none"
					/>
					<button
						type="submit"
						class="shrink-0 rounded border border-slate-700 px-2 py-1 font-semibold text-slate-300 hover:border-cyan-500 hover:text-cyan-400"
					>
						Set
					</button>
				</form>
				{#if battle.role === 'controller'}
					<span class="mt-1 block text-emerald-400">you are the controller</span>
				{:else if battle.role === 'spectator'}
					<span class="mt-1 block text-amber-400"
						>spectating -- enter the controller's token above to take control</span
					>
				{/if}
			</div>

			<div class:opacity-50={battle.role !== 'controller'}>
				<label for="player2-name" class="mb-1 block text-slate-500">Your trainer name</label>
				<form
					class="flex items-center gap-1.5"
					onsubmit={(e) => (e.preventDefault(), submitName())}
				>
					<input
						id="player2-name"
						bind:value={nameInput}
						maxlength="11"
						disabled={battle.role !== 'controller'}
						placeholder="e.g. Ash"
						class="w-full rounded border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200 placeholder-slate-600 focus:border-cyan-500 focus:outline-none disabled:cursor-not-allowed"
					/>
					<button
						type="submit"
						disabled={battle.role !== 'controller'}
						class="shrink-0 rounded border border-slate-700 px-2 py-1 font-semibold text-slate-300 hover:border-cyan-500 hover:text-cyan-400 disabled:cursor-not-allowed disabled:hover:border-slate-700 disabled:hover:text-slate-300"
					>
						Set
					</button>
				</form>
				{#if battle.myName && battle.nameConfirmed === battle.myName}
					<span class="mt-1 block text-emerald-400">active in mGBA</span>
				{:else if battle.myName}
					<span class="mt-1 block text-amber-400">not yet confirmed by mGBA</span>
				{/if}
			</div>

			<div class:opacity-50={battle.role !== 'controller'}>
				<label class="flex items-center justify-between gap-2">
					<span class="text-slate-500">Screenshot stream</span>
					<input
						type="checkbox"
						checked={streamSettings.enabled}
						disabled={battle.role !== 'controller'}
						onchange={(e) => streamSettings.setEnabled(e.currentTarget.checked)}
						class="h-4 w-4 accent-cyan-500 disabled:cursor-not-allowed"
					/>
				</label>
				<p class="mt-1 text-[11px] text-slate-600">
					Sends periodic screenshots of the game to this browser. Turn off if you're already
					screen-sharing (e.g. in Discord) to save bandwidth over a tunnel.
				</p>

				<div class="mt-3 flex items-center justify-between gap-2">
					<label for="stream-fps" class="text-slate-500">Stream framerate</label>
					<span class="font-mono text-slate-300">{streamSettings.fps} fps</span>
				</div>
				<input
					id="stream-fps"
					type="range"
					min={MIN_STREAM_FPS}
					max={MAX_STREAM_FPS}
					step="1"
					value={streamSettings.fps}
					disabled={battle.role !== 'controller'}
					oninput={(e) => streamSettings.setFps(e.currentTarget.valueAsNumber)}
					class="mt-1 h-1 w-full cursor-pointer appearance-none rounded-full bg-slate-700/50 accent-cyan-500 hover:bg-slate-700/70 disabled:cursor-not-allowed"
				/>
			</div>

			<div>
				<label for="sprite-style" class="mb-1 block text-slate-500">Sprites</label>
				<select
					id="sprite-style"
					value={spriteSettings.styleId}
					onchange={(e) => spriteSettings.setStyle(e.currentTarget.value)}
					class="w-full rounded border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200 focus:border-cyan-500 focus:outline-none"
				>
					{#each spriteGroups as group (group)}
						<optgroup label={group}>
							{#each SPRITE_STYLES.filter((s) => s.group === group) as s (s.id)}
								<option value={s.id}>{s.label}</option>
							{/each}
						</optgroup>
					{/each}
				</select>
			</div>
		</div>
	{/if}
</header>
