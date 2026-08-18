export interface YTPlayer {
	loadVideoById(videoId: string): void;
	playVideo(): void;
	pauseVideo(): void;
	seekTo(seconds: number, allowSeekAhead: boolean): void;
	setVolume(volume: number): void;
	getVolume(): number;
}

export interface YTPlayerEvent {
	data: number;
	target: YTPlayer;
}

export interface YTPlayerOptions {
	height?: string | number;
	width?: string | number;
	videoId?: string;
	playerVars?: Record<string, number | string>;
	events?: {
		onReady?: (event: { target: YTPlayer }) => void;
		onStateChange?: (event: YTPlayerEvent) => void;
		onError?: (event: { data: number }) => void;
	};
}

declare global {
	interface Window {
		YT?: {
			Player: new (elementId: string, options: YTPlayerOptions) => YTPlayer;
		};
		onYouTubeIframeAPIReady?: () => void;
	}
}
