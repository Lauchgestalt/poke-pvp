<script lang="ts">
	import './layout.css';
	import favicon from '$lib/assets/favicon.svg';
	import MusicPlayer from '$lib/components/MusicPlayer.svelte';
	import { battle } from '$lib/battleConnection.svelte';
	import { streamSettings } from '$lib/streamSettings.svelte';

	let { children } = $props();

	$effect(() => {
		if (battle.connected) {
			battle.setStreamEnabled(streamSettings.enabled);
			battle.setStreamFps(streamSettings.fps);
		}
	});
</script>

<svelte:head><link rel="icon" href={favicon} /></svelte:head>
{@render children()}
<MusicPlayer />
