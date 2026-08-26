const TARGET_FIRST_STORAGE_KEY = 'pokepvp-target-first-mode';

class BattleSettings {
	targetFirstMode = $state(
		typeof localStorage !== 'undefined'
			? localStorage.getItem(TARGET_FIRST_STORAGE_KEY) === 'true'
			: false
	);

	setTargetFirstMode(value: boolean) {
		this.targetFirstMode = value;
		if (typeof localStorage !== 'undefined') {
			localStorage.setItem(TARGET_FIRST_STORAGE_KEY, String(value));
		}
	}
}

export const battleSettings = new BattleSettings();
