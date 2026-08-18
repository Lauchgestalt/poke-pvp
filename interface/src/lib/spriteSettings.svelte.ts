import { DEFAULT_SPRITE_STYLE_ID } from './data/spriteStyles';

const STORAGE_KEY = 'pokepvp-sprite-style';

class SpriteSettings {
	styleId = $state(
		(typeof localStorage !== 'undefined' && localStorage.getItem(STORAGE_KEY)) ||
			DEFAULT_SPRITE_STYLE_ID
	);

	setStyle(id: string) {
		this.styleId = id;
		if (typeof localStorage !== 'undefined') localStorage.setItem(STORAGE_KEY, id);
	}
}

export const spriteSettings = new SpriteSettings();
