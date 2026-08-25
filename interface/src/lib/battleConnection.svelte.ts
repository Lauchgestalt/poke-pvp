import { MOVE_NAMES } from './data/moveNames';
import { SPECIES_NAMES } from './data/speciesNames';
import type {
	ActionChoice,
	AuthResult,
	Authenticate,
	BattleEnded,
	BattleLog,
	BattleStarted,
	BattleState,
	Player2NameAck,
	PlayerInfo,
	SetPlayer2Name,
	SetStreamEnabled,
	SetStreamFps
} from './types';

const RECONNECT_DELAY_MS = 2000;
const MAX_LOG_ENTRIES = 50;
const MY_NAME_STORAGE_KEY = 'pokepvp-player2-name';
const AUTH_TOKEN_STORAGE_KEY = 'pokepvp-controller-token';

function wsUrl(): string {
	const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
	return `${protocol}//${window.location.host}/ws`;
}

class BattleConnection {
	status = $state('connecting...');
	connected = $state(false);
	battleState = $state<BattleState | null>(null);
	battleState3 = $state<BattleState | null>(null);
	submitted = $state(false);
	submitted3 = $state(false);
	log = $state<string[]>([]);
	playerName = $state<string | null>(null);
	myName = $state<string | null>(
		typeof localStorage !== 'undefined' ? localStorage.getItem(MY_NAME_STORAGE_KEY) : null
	);
	nameConfirmed = $state<string | null>(null);
	role = $state<'unknown' | 'controller' | 'spectator'>('unknown');
	authToken = $state<string | null>(
		typeof localStorage !== 'undefined' ? localStorage.getItem(AUTH_TOKEN_STORAGE_KEY) : null
	);
	latestFrameUrl = $state<string | null>(null);

	private ws: WebSocket | null = null;
	private started = false;
	private frameObjectUrl: string | null = null;

	connect() {
		if (this.started) return;
		this.started = true;
		this.open();
	}

	private open() {
		this.ws = new WebSocket(wsUrl());

		this.ws.onopen = () => {
			this.connected = true;
			this.status = 'connected -- waiting for a battle...';
			this.nameConfirmed = null;
			this.role = 'unknown';
			if (this.authToken) this.sendAuthToken(this.authToken);
			if (this.myName) this.sendMyName(this.myName);
		};

		this.ws.onclose = () => {
			this.connected = false;
			this.status = 'disconnected, retrying in 2s...';
			setTimeout(() => this.open(), RECONNECT_DELAY_MS);
		};

		this.ws.onerror = () => {
			this.connected = false;
			this.status = 'connection error';
		};

		this.ws.onmessage = (event: MessageEvent<string | Blob>) => {
			if (event.data instanceof Blob) {
				if (this.frameObjectUrl) URL.revokeObjectURL(this.frameObjectUrl);
				this.frameObjectUrl = URL.createObjectURL(event.data);
				this.latestFrameUrl = this.frameObjectUrl;
				return;
			}

			let msg: unknown;
			try {
				msg = JSON.parse(event.data);
			} catch {
				console.error('bad message', event.data);
				return;
			}
			if (isBattleStarted(msg)) {
				this.log = [];
				this.battleState3 = null;
				if (this.frameObjectUrl) URL.revokeObjectURL(this.frameObjectUrl);
				this.frameObjectUrl = null;
				this.latestFrameUrl = null;
			} else if (isBattleEnded(msg)) {
				this.battleState = null;
				this.battleState3 = null;
				this.submitted = false;
				this.submitted3 = false;
				this.log = [];
				this.status = 'connected -- waiting for a battle...';
			} else if (isBattleState(msg)) {
				if (msg.battlerSlot === 3) {
					this.battleState3 = msg;
					if (msg.type === 'battle_state') this.submitted3 = false;
				} else {
					this.battleState = msg;
					if (msg.type === 'battle_state') this.submitted = false;
				}
				if (msg.type === 'battle_state') {
					this.status = msg.mustSwitch
						? 'your Pokemon fainted -- choose a replacement'
						: 'your turn -- pick a move, or switch below';
				}
			} else if (isBattleLog(msg)) {
				this.pushLog(this.formatLogEntry(msg));
			} else if (isPlayerInfo(msg)) {
				this.playerName = msg.name;
			} else if (isPlayer2NameAck(msg)) {
				this.nameConfirmed = msg.name;
			} else if (isAuthResult(msg)) {
				this.role = msg.role;
			}
		};
	}

	private send(
		msg: ActionChoice | SetPlayer2Name | SetStreamEnabled | SetStreamFps | Authenticate
	) {
		if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
		this.ws.send(JSON.stringify(msg));
	}

	chooseMove(moveIndex: number, battlerSlot: 1 | 3 = 1, target?: 0 | 2) {
		this.send({ type: 'action_choice', battlerSlot, action: 'move', moveIndex, target });
		if (battlerSlot === 3) this.submitted3 = true;
		else this.submitted = true;
		this.status = `sent move ${moveIndex}, waiting for next turn...`;
	}

	chooseSwitch(partySlot: number, battlerSlot: 1 | 3 = 1) {
		this.send({ type: 'action_choice', battlerSlot, action: 'switch', partySlot });
		if (battlerSlot === 3) this.submitted3 = true;
		else this.submitted = true;
		this.status = `sent switch to slot ${partySlot}, waiting for next turn...`;
	}

	chooseItem(itemId: number, battlerSlot: 1 | 3 = 1) {
		this.send({ type: 'action_choice', battlerSlot, action: 'item', itemId });
		if (battlerSlot === 3) this.submitted3 = true;
		else this.submitted = true;
		this.status = `sent item choice, waiting for next turn...`;
	}

	setStreamEnabled(enabled: boolean) {
		this.send({ type: 'set_stream_enabled', enabled });
	}

	setStreamFps(fps: number) {
		this.send({ type: 'set_stream_fps', fps });
	}

	setAuthToken(token: string) {
		const trimmed = token.trim();
		if (!trimmed) return;
		this.authToken = trimmed;
		localStorage.setItem(AUTH_TOKEN_STORAGE_KEY, trimmed);
		this.sendAuthToken(trimmed);
	}

	private sendAuthToken(token: string) {
		this.send({ type: 'authenticate', token });
	}

	setMyName(name: string) {
		const trimmed = name.trim();
		if (!trimmed) return;
		this.myName = trimmed;
		localStorage.setItem(MY_NAME_STORAGE_KEY, trimmed);
		this.sendMyName(trimmed);
	}

	private sendMyName(name: string) {
		this.send({ type: 'set_player2_name', name });
	}

	private pushLog(entry: string) {
		this.log = [...this.log, entry].slice(-MAX_LOG_ENTRIES);
	}

	private formatLogEntry(msg: BattleLog): string {
		const isPlayerOne = msg.battler === 0 || msg.battler === 2;
		const baseName = isPlayerOne ? (this.playerName ?? 'Player 1') : (this.myName ?? 'Player 2');
		const who = msg.battler === 2 || msg.battler === 3 ? `${baseName} (right)` : baseName;
		const species = SPECIES_NAMES[msg.speciesId] ?? `Species #${msg.speciesId}`;
		if (msg.event === 'move') {
			const name = MOVE_NAMES[msg.moveId] ?? `Move #${msg.moveId}`;
			if (msg.missed) {
				return `${species} (${who}) used ${name}! But it missed!`;
			}
			const damageSuffix =
				msg.damage === undefined
					? ''
					: msg.damage < 0
						? ` (restored ${-msg.damage} HP)`
						: ` (-${msg.damage} HP)`;
			return `${species} (${who}) used ${name}!${damageSuffix}`;
		}
		return `${who} sent out ${species}!`;
	}
}

function isBattleState(msg: unknown): msg is BattleState {
	const type = (msg as { type?: unknown } | null)?.type;
	return (
		typeof msg === 'object' && msg !== null && (type === 'battle_state' || type === 'battle_update')
	);
}

function isBattleStarted(msg: unknown): msg is BattleStarted {
	return (
		typeof msg === 'object' && msg !== null && (msg as { type?: unknown }).type === 'battle_started'
	);
}

function isBattleEnded(msg: unknown): msg is BattleEnded {
	return (
		typeof msg === 'object' && msg !== null && (msg as { type?: unknown }).type === 'battle_ended'
	);
}

function isBattleLog(msg: unknown): msg is BattleLog {
	return (
		typeof msg === 'object' && msg !== null && (msg as { type?: unknown }).type === 'battle_log'
	);
}

function isPlayerInfo(msg: unknown): msg is PlayerInfo {
	return (
		typeof msg === 'object' && msg !== null && (msg as { type?: unknown }).type === 'player_info'
	);
}

function isPlayer2NameAck(msg: unknown): msg is Player2NameAck {
	return (
		typeof msg === 'object' &&
		msg !== null &&
		(msg as { type?: unknown }).type === 'player2_name_ack'
	);
}

function isAuthResult(msg: unknown): msg is AuthResult {
	return (
		typeof msg === 'object' && msg !== null && (msg as { type?: unknown }).type === 'auth_result'
	);
}

export const battle = new BattleConnection();
