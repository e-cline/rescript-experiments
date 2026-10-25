import {readFileSync} from 'node:fs';
import {join} from 'node:path';

import {parseAst} from 'vite';
import {describe, expect, test} from 'vite-plus/test';

import {
  namesOnly,
  resolveSheet,
  sheetOfPath,
  sheetPath,
  stripStyles,
} from '../src/internal/css.js';
import {fixtures} from './support.js';

describe('sheet modules', () => {
  const root = '/app';

  test('resolve to a path under node_modules/.weft-css, queries kept', () => {
    expect(resolveSheet(root, 'virtual:weft/css/wabc123.css')).toBe(
      '/app/node_modules/.weft-css/wabc123.css',
    );
    expect(resolveSheet(root, 'virtual:weft/css/wabc123.css?url')).toBe(
      '/app/node_modules/.weft-css/wabc123.css?url',
    );
    // Vite's CSS plugin imports the resolved id again, with queries of its own.
    expect(
      resolveSheet(
        root,
        '/app/node_modules/.weft-css/wabc123.css?transform-only',
      ),
    ).toBe('/app/node_modules/.weft-css/wabc123.css?transform-only');
  });

  test("resolve the dev server's URL for a sheet to the same path", () => {
    expect(
      resolveSheet(root, '/node_modules/.weft-css/wabc123.css?direct'),
    ).toBe('/app/node_modules/.weft-css/wabc123.css?direct');
  });

  test("leave alone what isn't a sheet", () => {
    expect(resolveSheet(root, 'virtual:weft/css/nope.css')).toBeUndefined();
    expect(resolveSheet(root, 'virtual:weft/css/wabc123.js')).toBeUndefined();
    expect(resolveSheet(root, '/app/src/App.css')).toBeUndefined();
  });

  test('know their sheet id', () => {
    expect(sheetOfPath(sheetPath(root, 'wabc123'))).toBe('wabc123');
    expect(sheetOfPath(`${sheetPath(root, 'wabc123')}?direct`)).toBe('wabc123');
    expect(sheetOfPath('/app/src/wabc123.css')).toBeUndefined();
  });
});

describe('stripStyles', () => {
  const parse = (code: string) => parseAst(code);

  test('replaces each style call with its name, and a global with nothing, in place', () => {
    const code = `let a = "größe";
let x = Css$WeftCss.Internal.class_("A-x_wabc123", undefined, () => ({
  color: "red"
}));
Css$WeftCss.Internal.global_("A-global0_wabc123", "body", undefined, () => ({}));
let v = WeftCss.Css.Internal.var_("--A-v_wabc123", () => "#fff");
let other = Css$WeftCss.cx([x]);
`;
    const stripped = stripStyles(code, parse);
    expect(stripped.length).toBe(code.length);
    expect(stripped.split('\n').length).toBe(code.split('\n').length);
    expect(stripped.replace(/ +/g, ' ')).toBe(`let a = "größe";
let x = "A-x_wabc123" 
 
 ;
void 0 ;
let v = "--A-v_wabc123" ;
let other = Css$WeftCss.cx([x]);
`);
  });

  test("leaves calls that aren't the PPX's alone", () => {
    const code = `let a = Other.class_("x", () => 1);
let b = Css$WeftCss.Internal.class_(name, () => 1);
let c = Css$WeftCss.Internal.other_("x", () => 1);
`;
    expect(stripStyles(code, parse)).toBe(code);
  });

  test("leaves nothing of a compiled file's definitions", () => {
    const code = readFileSync(join(fixtures, 'styled/src/Card.res.js'), 'utf8');
    const stripped = stripStyles(code, parse);
    expect(code).toContain('DEFINITION_SENTINEL_CARD');
    expect(stripped).not.toContain('DEFINITION_SENTINEL_CARD');
    expect(stripped).not.toContain('Internal.');
    expect(stripped).not.toContain('Css$WeftCss.frame');
  });
});

describe('namesOnly', () => {
  const parse = (code: string) => parseAst(code);
  const file = (definition: string, extra = '') =>
    `let x = Css$WeftCss.Internal.class_("A-x_wabc123", undefined, () => (${definition}));\n${extra}`;

  test('is the same when only a definition changed', () => {
    expect(namesOnly(file('{color: "red"}'), parse)).toBe(
      namesOnly(
        file('{\n  color: "blue",\n  padding: {TAG: "Px", _0: 4}\n}'),
        parse,
      ),
    );
  });

  test('differs when the code did: a style added, or other code changed', () => {
    const before = namesOnly(file('{}'), parse);
    expect(
      namesOnly(
        file(
          '{}',
          'let y = Css$WeftCss.Internal.class_("A-y_wabc123", undefined, () => ({}));\n',
        ),
        parse,
      ),
    ).not.toBe(before);
    expect(namesOnly(file('{}', 'let z = 1;\n'), parse)).not.toBe(before);
  });
});
