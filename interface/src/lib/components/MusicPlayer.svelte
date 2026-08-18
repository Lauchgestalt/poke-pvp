<script lang="ts">
	import { battle } from '$lib/battleConnection.svelte';
	import { musicSettings } from '$lib/musicSettings.svelte';
	import { BATTLE_TRACKS, OVERWORLD_TRACKS, type MusicTrack } from '$lib/data/musicTracks';
	import type { YTPlayer, YTPlayerEvent } from '$lib/youtube';

	import { Play, Pause, SkipForward, Volume2, Volume1 } from '@lucide/svelte';

	const CROSSFADE_MS = 1500;
	const CROSSFADE_STEP_MS = 50;
	const MAX_VOLUME = $derived(musicSettings.volume * 100);

	type Category = 'battle' | 'overworld';

	let playerA: YTPlayer | null = null;
	let playerB: YTPlayer | null = null;
	let activeIsA = true;
	let currentCategory: Category | null = null;
	let currentTrackId: string | null = null;
	let ready = $state(false);
	let initPromise: Promise<void> | null = null;
	let crossfadeTimer: ReturnType<typeof setInterval> | undefined;
	let playing = $state(false);
	let loading = $state(false);
	let currentSong = $state('');

	function pickTrack(category: Category): MusicTrack {
		const pool = category === 'battle' ? BATTLE_TRACKS : OVERWORLD_TRACKS;
		const others = pool.filter((t) => t.videoId !== currentTrackId);
		const choices = others.length > 0 ? others : pool;
		return choices[Math.floor(Math.random() * choices.length)];
	}

	function loadYouTubeApi(): Promise<void> {
		return new Promise((resolve) => {
			if (window.YT?.Player) {
				resolve();
				return;
			}
			const existing = window.onYouTubeIframeAPIReady;
			window.onYouTubeIframeAPIReady = () => {
				existing?.();
				resolve();
			};
			if (!document.querySelector('script[src*="youtube.com/iframe_api"]')) {
				const script = document.createElement('script');
				script.src = 'https://www.youtube.com/iframe_api';
				document.head.appendChild(script);
			}
		});
	}

	function createPlayer(elementId: string): Promise<YTPlayer> {
		return new Promise((resolve) => {
			const player = new window.YT!.Player(elementId, {
				height: '1',
				width: '1',
				playerVars: { autoplay: 0, controls: 0, disablekb: 1, modestbranding: 1, rel: 0 },
				events: {
					onReady: () => resolve(player),
					onStateChange: (e: YTPlayerEvent) => {
						const activePlayer = activeIsA ? playerA : playerB;
						if (e.data === 0 && e.target === activePlayer) {
							crossfadeTo(pickTrack(currentCategory ?? 'overworld'));
						}
					}
				}
			});
		});
	}

	async function init(): Promise<void> {
		if (!initPromise) {
			initPromise = (async () => {
				await loadYouTubeApi();
				[playerA, playerB] = await Promise.all([
					createPlayer('yt-player-a'),
					createPlayer('yt-player-b')
				]);
				playerA.setVolume(0);
				playerB.setVolume(0);
				ready = true;
			})();
		}
		return initPromise;
	}

	function crossfadeTo(track: MusicTrack) {
		if (!playerA || !playerB) return;
		const from = activeIsA ? playerA : playerB;
		const to = activeIsA ? playerB : playerA;

		to.loadVideoById(track.videoId);
		to.setVolume(0);
		to.playVideo();
		currentTrackId = track.videoId;
		currentSong = track.title;

		clearInterval(crossfadeTimer);
		const steps = Math.round(CROSSFADE_MS / CROSSFADE_STEP_MS);
		let step = 0;
		crossfadeTimer = setInterval(() => {
			step++;
			const t = Math.min(1, step / steps);
			from.setVolume(Math.round(MAX_VOLUME * (1 - t)));
			to.setVolume(Math.round(MAX_VOLUME * t));
			if (t >= 1) {
				clearInterval(crossfadeTimer);
				crossfadeTimer = undefined;
				from.pauseVideo();
				activeIsA = !activeIsA;
			}
		}, CROSSFADE_STEP_MS);
	}

	async function enableMusic() {
		musicSettings.setEnabled(true);
		loading = true;
		try {
			await init();
		} finally {
			loading = false;
		}
		const category: Category = battle.battleState ? 'battle' : 'overworld';
		currentCategory = category;
		let pickedSong = pickTrack(category);
		crossfadeTo(pickedSong);
		playing = true;
		currentSong = pickedSong.title;
	}

	function disableMusic() {
		musicSettings.setEnabled(false);
		clearInterval(crossfadeTimer);
		crossfadeTimer = undefined;
		playerA?.pauseVideo();
		playerB?.pauseVideo();
		playing = false;
	}

	$effect(() => {
		const target = MAX_VOLUME;
		if (playing && !crossfadeTimer) {
			(activeIsA ? playerA : playerB)?.setVolume(Math.round(target));
		}
	});

	$effect(() => {
		const category: Category = battle.battleState ? 'battle' : 'overworld';
		if (playing && category !== currentCategory) {
			currentCategory = category;
			crossfadeTo(pickTrack(category));
		}
	});
</script>

<div
	style="position: absolute; left: -9999px; top: -9999px; width: 1px; height: 1px; overflow: hidden;"
>
	<div id="yt-player-a"></div>
	<div id="yt-player-b"></div>
</div>

<div id="music-controller" class="fixed right-4 bottom-4 z-30 flex flex-col items-end gap-2">
	<p class="z-30 m-auto text-xs font-semibold text-slate-300 shadow-lg backdrop-blur-sm">
		{#if loading}
			Loading music...
		{:else}
			{currentSong}
		{/if}
	</p>
	<div class="flex gap-2">
		<div
			class="z-30 flex items-center gap-1.5 rounded-full border border-slate-700 bg-slate-900/90 px-3 py-2 text-xs font-semibold text-slate-300 shadow-lg backdrop-blur-sm hover:border-cyan-500 hover:text-cyan-400"
		>
			<Volume1 />
			<input
				type="range"
				min="0"
				max="1"
				step="0.01"
				value={musicSettings.volume}
				oninput={(e) => musicSettings.setVolume(parseFloat(e.currentTarget.value))}
				class="h-1 w-24 cursor-pointer appearance-none rounded-full bg-slate-700/50 accent-cyan-500 hover:bg-slate-700/70"
			/>
			<Volume2 />
		</div>
		<button
			type="button"
			aria-label={playing ? 'Pause music' : 'Play music'}
			onclick={() => (playing ? disableMusic() : enableMusic())}
			class="z-30 flex items-center gap-1.5 rounded-full border border-slate-700 bg-slate-900/90 px-3 py-2 text-xs font-semibold text-slate-300 shadow-lg backdrop-blur-sm hover:border-cyan-500 hover:text-cyan-400"
		>
			{#if playing}
				<Pause />
			{:else}
				<Play />
			{/if}
		</button>
		<button
			type="button"
			aria-label="Skip to a different track"
			onclick={() => {
				if (!ready || !playing) return;
				const category: Category = battle.battleState ? 'battle' : 'overworld';
				crossfadeTo(pickTrack(category));
			}}
			class="z-30 flex items-center gap-1.5 rounded-full border border-slate-700 bg-slate-900/90 px-3 py-2 text-xs font-semibold text-slate-300 shadow-lg backdrop-blur-sm hover:border-cyan-500 hover:text-cyan-400"
		>
			<SkipForward />
		</button>
	</div>
</div>
