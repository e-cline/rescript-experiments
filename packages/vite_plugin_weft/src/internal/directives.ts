// The directives `ppx_weft` writes at the top of a compiled file: `'use weft server'` in a server
// file (one with server components, or `@@weft.server`), `'use weft entrypoint'` in one with
// entrypoints, and `'use weft rpc <id>'` for each RPC a file declares (beside an entrypoint one, or
// alone in a shared file).

/** What a file is, from its directives: a shared file declaring RPCs has no other directive. */
export type Kind = 'server' | 'entrypoint' | 'shared';

export type Directive = {
  /** `rpc` for an RPC's declaration, whose ID is `rpc`. */
  kind: 'server' | 'entrypoint' | 'rpc';
  rpc?: string;
  /** Where the directive's statement is, its `;` included if it has one. */
  start: number;
  end: number;
};

/** A file's Weft directives, and what they say. */
export type Directives = {
  kind: Kind;
  /** The IDs of the RPCs it declares, in order. */
  rpcs: string[];
  directives: Directive[];
};

const kinds: Record<string, 'server' | 'entrypoint'> = {
  'use weft server': 'server',
  'use weft entrypoint': 'entrypoint',
};

const rpcPrefix = 'use weft rpc ';
/** An RPC ID, as `WeftServer.Rpc.isValidId` (and the PPX) has it. */
const rpcId = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*$/;

/** Skips whitespace and comments from `at`, returning where the next token starts. */
function skipTrivia(code: string, at: number, stopAtNewline = false): number {
  let i = at;
  while (i < code.length) {
    const char = code[i];
    if (char === '\n' && stopAtNewline) {
      return i;
    } else if (
      char === ' ' ||
      char === '\t' ||
      char === '\r' ||
      char === '\n'
    ) {
      i++;
    } else if (code.startsWith('//', i)) {
      const newline = code.indexOf('\n', i);
      i = newline === -1 ? code.length : newline;
    } else if (code.startsWith('/*', i)) {
      const close = code.indexOf('*/', i + 2);
      i = close === -1 ? code.length : close + 2;
    } else {
      return i;
    }
  }
  return i;
}

/** The end of the string literal starting at `at` (its closing quote's index plus one), if it is one. */
function stringEnd(code: string, at: number): number | undefined {
  const quote = code[at];
  if (quote !== "'" && quote !== '"') return undefined;
  for (let i = at + 1; i < code.length; i++) {
    const char = code[i];
    if (char === '\\') {
      i++;
    } else if (char === quote) {
      return i + 1;
    } else if (char === '\n') {
      return undefined;
    }
  }
  return undefined;
}

/**
 * The Weft directives in `code`'s directive prologue (the string-literal statements a module starts
 * with, which is where `'use strict'` goes), if it has any.
 */
export function findDirectives(code: string): Directives | undefined {
  // Most modules have no directive at all: don't scan them.
  if (!code.includes('use weft ')) return undefined;
  const directives: Directive[] = [];
  let at = skipTrivia(code, 0);
  for (;;) {
    const end = stringEnd(code, at);
    if (end === undefined) break;
    // A string literal is a directive only as a statement of its own: `'a'.length` isn't one.
    const after = skipTrivia(code, end, true);
    const next = code[after];
    let statementEnd: number;
    if (next === ';') {
      statementEnd = after + 1;
    } else if (next === undefined || next === '\n') {
      statementEnd = end;
    } else {
      break;
    }
    const text = code.slice(at + 1, end - 1);
    const kind = kinds[text];
    if (kind !== undefined) {
      directives.push({kind, start: at, end: statementEnd});
    } else if (text.startsWith(rpcPrefix)) {
      const id = text.slice(rpcPrefix.length);
      if (rpcId.test(id)) {
        directives.push({kind: 'rpc', rpc: id, start: at, end: statementEnd});
      }
    }
    at = skipTrivia(code, statementEnd);
  }
  if (directives.length === 0) return undefined;
  const has = (kind: Directive['kind']) =>
    directives.some((directive) => directive.kind === kind);
  return {
    kind: has('server')
      ? 'server'
      : has('entrypoint')
        ? 'entrypoint'
        : 'shared',
    rpcs: directives.flatMap(({rpc}) => (rpc === undefined ? [] : [rpc])),
    directives,
  };
}

/**
 * `code` without its Weft directives (bundlers warn about module-level directives they don't
 * know), or `undefined` if it has none. They're blanked out rather than removed, so every other
 * position in the file stays where it was and no source map is needed.
 */
export function stripDirectives(
  code: string,
  found = findDirectives(code),
): string | undefined {
  if (found === undefined) return undefined;
  let stripped = code;
  for (const {start, end} of found.directives) {
    stripped =
      stripped.slice(0, start) + ' '.repeat(end - start) + stripped.slice(end);
  }
  return stripped;
}
