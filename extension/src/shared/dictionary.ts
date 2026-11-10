export type DictionarySense = {
  pos: string | null;
  domain: string | null;
  zh: string;
};

export type DictionaryEntry = {
  text: string;
  kind: string;
  match: string;
  lemma: string | null;
  phonetic: string | null;
  senses: DictionarySense[];
};

export type LookupResponse =
  | { ok: true; entry: DictionaryEntry }
  | { ok: false; error: LookupError };

export type LookupError = 'too_long' | 'unavailable' | 'failed' | 'invalid_response';
