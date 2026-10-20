// What the runner reports to the show (the studio's `show/show.ts`, `GameEvent`).
export type ObstacleKind = 'cactus' | 'cacti' | 'bird';

export type GameEvent =
	| { type: 'start' }
	| { type: 'restart' }
	| { type: 'milestone'; score: number }
	| { type: 'night' }
	| { type: 'idle' }
	| { type: 'crash'; score: number; best: number; newHigh: boolean; obstacle: ObstacleKind }
	/** The last life is gone: GAME OVER. Rex already roasted the crash. */
	| { type: 'over' };
