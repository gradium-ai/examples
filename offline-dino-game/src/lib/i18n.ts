// The studio's `$t`, reduced to what this page needs: English only, `{name}` placeholders.
import { readable } from 'svelte/store';
import { phonon } from './messages';

const messages: Record<string, string> = phonon;
export type MessageKey = keyof typeof phonon;

function translate(key: string, params: Record<string, string | number> = {}): string {
	const text = messages[key] ?? key;
	return text.replace(/\{(\w+)\}/g, (m, name) => (name in params ? String(params[name]) : m));
}

export const t = readable(translate);
