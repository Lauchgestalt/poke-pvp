export interface ActiveMon {
	species: number;
	hp: number;
	maxHp: number;
	level: number;
	nickname: string;
	status?: string | null;
	gender?: 'male' | 'female' | null;
}

export interface PartyMon extends ActiveMon {
	partySlot: number;
	moveIds: number[];
	pp: number[];
}

export interface BattleState {
	type: 'battle_state' | 'battle_update';
	battlerSlot: 1 | 3;
	mustSwitch: boolean;
	enemyMoveIds: number[];
	pp: number[];
	enemyActive: ActiveMon;
	playerActive: ActiveMon;
	playerActive2: ActiveMon | null;
	enemyActivePartySlot: number;
	enemyParty: PartyMon[];
	availableItems: { itemId: number; count: number }[];
}

export interface BattleEnded {
	type: 'battle_ended';
}

export interface BattleStarted {
	type: 'battle_started';
}

export interface PlayerInfo {
	type: 'player_info';
	name: string;
}

export type Battler = 0 | 1 | 2 | 3;

export type BattleLog =
	| {
			type: 'battle_log';
			battler: Battler;
			event: 'move';
			moveId: number;
			speciesId: number;
			damage?: number;
			missed?: boolean;
	  }
	| { type: 'battle_log'; battler: Battler; event: 'switch'; speciesId: number }
	| { type: 'battle_log'; battler: Battler | null; event: 'text'; text: string };

export type ActionChoice =
	| {
			type: 'action_choice';
			battlerSlot: 1 | 3;
			action: 'move';
			moveIndex: number;
			target?: 0 | 2;
	  }
	| { type: 'action_choice'; battlerSlot: 1 | 3; action: 'switch'; partySlot: number }
	| { type: 'action_choice'; battlerSlot: 1 | 3; action: 'item'; itemId: number };

export interface SetPlayer2Name {
	type: 'set_player2_name';
	name: string;
}

export interface Player2NameAck {
	type: 'player2_name_ack';
	name: string;
}

export interface SetStreamEnabled {
	type: 'set_stream_enabled';
	enabled: boolean;
}

export interface SetStreamFps {
	type: 'set_stream_fps';
	fps: number;
}

export interface Authenticate {
	type: 'authenticate';
	token: string;
}

export interface AuthResult {
	type: 'auth_result';
	role: 'controller' | 'spectator';
	reason?: 'invalid_token' | 'controller_taken';
}
