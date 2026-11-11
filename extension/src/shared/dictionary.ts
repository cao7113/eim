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

export type LookupError =
  | 'too_long'
  | 'disabled'
  | 'unavailable'
  | 'failed'
  | 'invalid_response';

export type DictionaryConnection =
  | { status: 'connected' }
  | { status: 'offline' }
  | { status: 'unconfigured' };

export type ExtensionAccount =
  | { status: 'signed_out' }
  | { status: 'signed_in'; email: string }
  | { status: 'offline'; email?: string };

export type ExtensionAuthResult =
  | { ok: true; account: Extract<ExtensionAccount, { status: 'signed_in' }> }
  | { ok: false; error: 'unavailable' | 'failed' };

export type ExtensionActionResult =
  | { ok: true }
  | { ok: false; error: 'unavailable' | 'failed' };

export type VocabEntryStatus =
  | { status: 'checking' }
  | { status: 'saved' }
  | { status: 'not_saved' }
  | { status: 'signed_out' }
  | { status: 'offline' };

export type VocabEntryActionResult =
  | { ok: true }
  | { ok: false; error: 'signed_out' | 'unavailable' | 'failed' };
