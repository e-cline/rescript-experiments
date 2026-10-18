// The directives `ppx_weft` writes at the top of a compiled file: `'use weft server'` in a file with
// server components, `'use weft entrypoint'` in one with entrypoints. A file has one or neither.

export type Kind = 'server' | 'entrypoint';

export type Directive = {
  kind: Kind;
  /** Where the directive's statement is, its `;` included if it has one. */
  start: number;
  end: number;
};

const kinds: Record<string, Kind> = {
  'use weft server': 'server',
  'use weft entrypoint': 'entrypoint',
};

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
 * The Weft directive in `code`'s directive prologue (the string-literal statements a module starts
 * with, which is where `'use strict'` goes), if it has one.
 */
export function findDirective(code: string): Directive | undefined {
  // Most modules have no directive at all: don't scan them.
  if (!code.includes('use weft ')) return undefined;
  let at = skipTrivia(code, 0);
  for (;;) {
    const end = stringEnd(code, at);
    if (end === undefined) return undefined;
    // A string literal is a directive only as a statement of its own: `'a'.length` isn't one.
    const after = skipTrivia(code, end, true);
    const next = code[after];
    let statementEnd: number;
    if (next === ';') {
      statementEnd = after + 1;
    } else if (next === undefined || next === '\n') {
      statementEnd = end;
    } else {
      return undefined;
    }
    const kind = kinds[code.slice(at + 1, end - 1)];
    if (kind !== undefined) return {kind, start: at, end: statementEnd};
    at = skipTrivia(code, statementEnd);
  }
}

/**
 * `code` without its Weft directive (bundlers warn about module-level directives they don't know),
 * or `undefined` if it has none. The directive is blanked out rather than removed, so every other
 * position in the file stays where it was and no source map is needed.
 */
export function stripDirective(
  code: string,
  directive = findDirective(code),
): string | undefined {
  if (directive === undefined) return undefined;
  return (
    code.slice(0, directive.start) +
    ' '.repeat(directive.end - directive.start) +
    code.slice(directive.end)
  );
}
