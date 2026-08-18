const STORAGE_KEY = 'pokepvp-music-enabled';

class MusicSettings {
	enabled = $state(
		typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_KEY) === 'true' : false
	);

	volume = $state(0.5);

	setEnabled(value: boolean) {
		this.enabled = value;
		if (typeof localStorage !== 'undefined') localStorage.setItem(STORAGE_KEY, String(value));
	}

	setVolume(value: number) {
		this.volume = value;
	}
}

export const musicSettings = new MusicSettings();
