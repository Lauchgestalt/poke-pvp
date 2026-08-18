export interface SpriteStyle {
	id: string;
	label: string;
	group: string;
	pixelArt: boolean;
	scale?: number;
	url: (nationalDexNumber: number) => string;
}

const BASE = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon';

export const DEFAULT_SPRITE_STYLE_ID = 'official-artwork';

export const SPRITE_STYLES: SpriteStyle[] = [
	{
		id: 'showdown',
		label: 'Showdown (animated)',
		group: 'Other',
		pixelArt: true,
		url: (n) => `${BASE}/other/showdown/${n}.gif`
	},
	{
		id: 'official-artwork',
		label: 'Official Artwork',
		group: 'Other',
		pixelArt: false,
		url: (n) => `${BASE}/other/official-artwork/${n}.png`
	},
	{
		id: 'home',
		label: 'Home',
		group: 'Other',
		pixelArt: false,
		url: (n) => `${BASE}/other/home/${n}.png`
	},
	{
		id: 'dream-world',
		label: 'Dream World',
		group: 'Other',
		pixelArt: false,
		url: (n) => `${BASE}/other/dream-world/${n}.svg`
	},
	{
		id: 'default',
		label: 'Classic',
		group: 'Other',
		pixelArt: true,
		url: (n) => `${BASE}/${n}.png`
	},

	{
		id: 'red-blue',
		label: 'Red & Blue',
		group: 'Generation I',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-i/red-blue/${n}.png`
	},
	{
		id: 'yellow',
		label: 'Yellow',
		group: 'Generation I',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-i/yellow/${n}.png`
	},

	{
		id: 'gold',
		label: 'Gold',
		group: 'Generation II',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-ii/gold/${n}.png`
	},
	{
		id: 'silver',
		label: 'Silver',
		group: 'Generation II',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-ii/silver/${n}.png`
	},
	{
		id: 'crystal',
		label: 'Crystal',
		group: 'Generation II',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-ii/crystal/${n}.png`
	},
	{
		id: 'crystal-animated',
		label: 'Crystal (animated)',
		group: 'Generation II',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-ii/crystal/animated/${n}.gif`
	},

	{
		id: 'emerald',
		label: 'Emerald',
		group: 'Generation III',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-iii/emerald/${n}.png`
	},
	{
		id: 'firered-leafgreen',
		label: 'FireRed & LeafGreen',
		group: 'Generation III',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-iii/firered-leafgreen/${n}.png`
	},
	{
		id: 'ruby-sapphire',
		label: 'Ruby & Sapphire',
		group: 'Generation III',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-iii/ruby-sapphire/${n}.png`
	},

	{
		id: 'diamond-pearl',
		label: 'Diamond & Pearl',
		group: 'Generation IV',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-iv/diamond-pearl/${n}.png`
	},
	{
		id: 'platinum',
		label: 'Platinum',
		group: 'Generation IV',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-iv/platinum/${n}.png`
	},
	{
		id: 'heartgold-soulsilver',
		label: 'HeartGold & SoulSilver',
		group: 'Generation IV',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-iv/heartgold-soulsilver/${n}.png`
	},

	{
		id: 'black-white',
		label: 'Black & White',
		group: 'Generation V',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-v/black-white/${n}.png`
	},
	{
		id: 'black-white-animated',
		label: 'Black & White (animated)',
		group: 'Generation V',
		pixelArt: true,
		url: (n) => `${BASE}/versions/generation-v/black-white/animated/${n}.gif`
	},

	{
		id: 'x-y',
		label: 'X & Y',
		group: 'Generation VI',
		pixelArt: false,
		url: (n) => `${BASE}/versions/generation-vi/x-y/${n}.png`
	},
	{
		id: 'omegaruby-alphasapphire',
		label: 'Omega Ruby & Alpha Sapphire',
		group: 'Generation VI',
		pixelArt: false,
		scale: 1.4,
		url: (n) => `${BASE}/versions/generation-vi/omegaruby-alphasapphire/${n}.png`
	},

	{
		id: 'ultra-sun-ultra-moon',
		label: 'Ultra Sun & Ultra Moon',
		group: 'Generation VII',
		pixelArt: false,
		url: (n) => `${BASE}/versions/generation-vii/ultra-sun-ultra-moon/${n}.png`
	},

	{
		id: 'brilliant-diamond-shining-pearl',
		label: 'Brilliant Diamond & Shining Pearl',
		group: 'Generation VIII',
		pixelArt: false,
		url: (n) => `${BASE}/versions/generation-viii/brilliant-diamond-shining-pearl/${n}.png`
	},

	{
		id: 'scarlet-violet',
		label: 'Scarlet & Violet',
		group: 'Generation IX',
		pixelArt: false,
		url: (n) => `${BASE}/versions/generation-ix/scarlet-violet/${n}.png`
	}
];

export const SPRITE_STYLES_BY_ID = new Map(SPRITE_STYLES.map((s) => [s.id, s]));
