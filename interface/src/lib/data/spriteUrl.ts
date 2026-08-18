import { SPECIES_TO_NATIONAL_DEX } from './speciesToNationalDex';
import { DEFAULT_SPRITE_STYLE_ID, SPRITE_STYLES_BY_ID } from './spriteStyles';
import { spriteSettings } from '../spriteSettings.svelte';

export function spriteUrl(speciesId: number, styleId: string = spriteSettings.styleId): string {
	const natDex = SPECIES_TO_NATIONAL_DEX[speciesId] ?? 0;
	if (!natDex) return '';
	const style = SPRITE_STYLES_BY_ID.get(styleId) ?? SPRITE_STYLES_BY_ID.get(DEFAULT_SPRITE_STYLE_ID)!;
	return style.url(natDex);
}

export function fallbackSpriteUrl(speciesId: number): string {
	return spriteUrl(speciesId, DEFAULT_SPRITE_STYLE_ID);
}

const knownBadUrls = new Set<string>();

export function isSpriteUrlKnownBad(url: string): boolean {
	return knownBadUrls.has(url);
}

export function markSpriteUrlFailed(url: string): void {
	knownBadUrls.add(url);
}
