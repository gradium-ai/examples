/**
 * The page's words, taken from the Phonon page of Gradium's studio (its English Phonon strings),
 * keeping only the ones this page uses. The maker's plate says the voice runs in this tab.
 * Text set in Komuna goes through `marquee()` (src/arcade/marquee.ts), which drops accents the
 * face does not have.
 *
 * What Rex says is not here: his lines are in `src/lines.js`.
 */
export const phonon = {
	// The page
	'phonon.back': 'Back to studio',
	'phonon.tagline': 'Open weights, on-device TTS',
	'phonon.mode.game': 'Offline FM',
	'phonon.mode.gameHint': 'Dino run game, live radio host voice',
	'phonon.stage.label': 'Choose a stage',
	'phonon.cabinet.title': 'Title screen',
	'phonon.cabinet.homeHint': 'Back to start',

	// Offline FM: the show, its voice and topics
	'phonon.show.tuneIn': 'Tap to tune in',
	'phonon.show.warmingUp': 'Rex is warming up the mic',
	'phonon.show.lostSignal': 'Rex lost the signal for a moment',
	'phonon.topic.label': 'Give Rex a topic',
	'phonon.stage1.voice': 'Voice',
	'phonon.stage1.prevVoice': 'Previous voice',
	'phonon.stage1.nextVoice': 'Next voice',
	'phonon.hud.seconds': '{seconds} s',

	// The game on the screen
	'phonon.game.score': 'Score {score}',
	'phonon.game.over': 'Game over',
	'phonon.arcade.player': '1UP',
	'phonon.arcade.hiScore': 'Hi-score',
	'phonon.arcade.konami': '99 credits. Rex approves.',
	'phonon.arcade.start': 'Start game',
	'phonon.arcade.pressStart': 'Press space or tap',
	'phonon.arcade.newHigh': 'New hi-score',
	'phonon.arcade.continue': 'Continue?',
	'phonon.arcade.yes': 'Yes',
	'phonon.arcade.no': 'No',
	'phonon.arcade.paused': 'Paused',
	'phonon.arcade.resume': 'Resume',

	// The cabinet: its keys, sound, coin door and plate
	'phonon.cabinet.controls': 'Controls',
	'phonon.cabinet.left': 'Left',
	'phonon.cabinet.right': 'Right',
	'phonon.keys.jump': 'Jump',
	'phonon.keys.duck': 'Duck',
	'phonon.keys.choose': 'Menu',
	'phonon.keys.pause': 'Pause',
	'phonon.keys.coin': 'Coin',
	'phonon.keys.start': 'Start',
	'phonon.keys.sound': 'Sound',
	'phonon.cabinet.soundOn': 'Sound on',
	'phonon.cabinet.soundOff': 'Sound off',
	'phonon.cabinet.volume': 'Volume',
	'phonon.arcade.insertCoin': 'Insert coin',
	'phonon.arcade.coins': 'Coins {credits}',
	'phonon.cabinet.plate': 'Powered by Phonon\non-device, in this tab',

	// The stickers: links out
	'phonon.cabinet.links': 'Get Phonon',
	'phonon.links.github': 'Source on GitHub',
	'phonon.links.huggingFace': 'Weights on Hugging Face',
	'phonon.links.website': 'Phonon on gradium.ai',
	'phonon.sticker.github': 'Fork the code',
	'phonon.sticker.huggingFace': 'Grab the weights',
	'phonon.sticker.website': 'Learn more',
};
