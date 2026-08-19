const ENABLED_STORAGE_KEY = 'pokepvp-stream-enabled';
const FPS_STORAGE_KEY = 'pokepvp-stream-fps';

export const MIN_STREAM_FPS = 5;
export const MAX_STREAM_FPS = 24;
const DEFAULT_STREAM_FPS = MAX_STREAM_FPS;

function clampFps(value: number): number {
	return Math.min(MAX_STREAM_FPS, Math.max(MIN_STREAM_FPS, Math.round(value)));
}

class StreamSettings {
	enabled = $state(
		typeof localStorage !== 'undefined'
			? localStorage.getItem(ENABLED_STORAGE_KEY) !== 'false'
			: true
	);
	fps = $state(
		typeof localStorage !== 'undefined'
			? clampFps(Number(localStorage.getItem(FPS_STORAGE_KEY)) || DEFAULT_STREAM_FPS)
			: DEFAULT_STREAM_FPS
	);

	setEnabled(value: boolean) {
		this.enabled = value;
		if (typeof localStorage !== 'undefined')
			localStorage.setItem(ENABLED_STORAGE_KEY, String(value));
	}

	setFps(value: number) {
		this.fps = clampFps(value);
		if (typeof localStorage !== 'undefined') {
			localStorage.setItem(FPS_STORAGE_KEY, String(this.fps));
		}
	}
}

export const streamSettings = new StreamSettings();
