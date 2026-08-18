import { SPECIES_TO_NATIONAL_DEX } from './speciesToNationalDex';

export function spriteUrl(speciesId: number): string {
	const natDex = SPECIES_TO_NATIONAL_DEX[speciesId] ?? 0;
	if (!natDex) return '';
	return `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/${natDex}.png`;
}
