<script lang="ts">
	import { spriteUrl, fallbackSpriteUrl, isSpriteUrlKnownBad, markSpriteUrlFailed } from '$lib/data/spriteUrl';
	import { spriteSettings } from '$lib/spriteSettings.svelte';
	import { SPRITE_STYLES_BY_ID, DEFAULT_SPRITE_STYLE_ID } from '$lib/data/spriteStyles';

	let {
		species,
		alt,
		class: className = '',
		style: extraStyle = ''
	}: {
		species: number;
		alt: string;
		class?: string;
		style?: string;
	} = $props();
	
	let failed = $state(false);
	$effect(() => {
		species;
		spriteSettings.styleId;
		failed = false;
	});

	const primaryUrl = $derived(spriteUrl(species));
	const fallbackUrl = $derived(fallbackSpriteUrl(species));
	const usingFallback = $derived(failed || (primaryUrl !== '' && isSpriteUrlKnownBad(primaryUrl)));

	const src = $derived.by(() => {
		if (!usingFallback) return primaryUrl;
		if (fallbackUrl && !isSpriteUrlKnownBad(fallbackUrl)) return fallbackUrl;
		return '';
	});

	const activeStyle = $derived(
		SPRITE_STYLES_BY_ID.get(usingFallback ? DEFAULT_SPRITE_STYLE_ID : spriteSettings.styleId)
	);
	const pixelArt = $derived(activeStyle?.pixelArt ?? true);
	const scale = $derived(activeStyle?.scale ?? 1);

	function handleError() {
		if (src) markSpriteUrlFailed(src);
		failed = true;
	}
</script>

{#if src}
	<div class="{className} overflow-hidden" style={extraStyle}>
		<img
			{src}
			{alt}
			class="h-full w-full object-contain {pixelArt ? '[image-rendering:pixelated]' : ''}"
			style={scale !== 1 ? `transform: scale(${scale});` : undefined}
			loading="lazy"
			onerror={handleError}
		/>
	</div>
{/if}
