const STORAGE_KEY = 'pokepvp-stream-enabled';

class StreamSettings {
	enabled = $state(
		typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_KEY) !== 'false' : true
	);

	setEnabled(value: boolean) {
		this.enabled = value;
		if (typeof localStorage !== 'undefined') localStorage.setItem(STORAGE_KEY, String(value));
	}
}

export const streamSettings = new StreamSettings();
