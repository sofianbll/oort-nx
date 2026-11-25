/* Names games give their settings, known whatever the case or the hyphens. Anything else is left as the game wrote it. */
export const plain = text => text.toLowerCase().replace(/[\s\-_]+/g, '');
export const gameWord = (words, text) => words && Object.hasOwn(words, plain(text)) ? words[plain(text)] : text;
