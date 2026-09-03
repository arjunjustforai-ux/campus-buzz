/** Tokenizer used to build `searchTokens` on events for prefix search. */
export function searchTokens(...texts: Array<string | undefined | null>): string[] {
  const out = new Set<string>();
  for (const t of texts) {
    if (!t) continue;
    for (const word of t.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, " ").split(/\s+/)) {
      if (word.length < 2) continue;
      out.add(word);
      for (let i = 3; i < word.length && i <= 12; i++) out.add(word.slice(0, i));
      if (out.size > 400) return [...out];
    }
  }
  return [...out];
}

export function referralCodeFor(uid: string, displayName: string): string {
  const base = (displayName || "buzz").replace(/[^a-z]/gi, "").slice(0, 4).toUpperCase().padEnd(4, "Z");
  let h = 0;
  for (let i = 0; i < uid.length; i++) h = (h * 33 + uid.charCodeAt(i)) >>> 0;
  return `${base}${(h % 10000).toString().padStart(4, "0")}`;
}

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export function humanCode(length = 8, rnd: () => number = Math.random): string {
  let s = "";
  for (let i = 0; i < length; i++) s += CODE_ALPHABET[Math.floor(rnd() * CODE_ALPHABET.length)];
  return `${s.slice(0, 4)}-${s.slice(4)}`;
}
