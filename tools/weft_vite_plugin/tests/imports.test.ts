import {dirname, join} from 'node:path';

import {afterAll, describe, expect, test} from 'vite-plus/test';

import {entrypointSheets} from '../src/internal/imports.js';
import {scan, sheetId} from '../src/internal/scan.js';
import {copyFixture, fixtureName, removeCopies} from './support.js';

afterAll(removeCopies);

const basic = fixtureName('basic');
const widgets = fixtureName('widgets');

describe('entrypointSheets', () => {
  test("follows each entrypoint file's static imports to the style files, its package's and others'", () => {
    const scanned = scan(copyFixture('basic'));
    expect(entrypointSheets(scanned)).toEqual({
      // Likes imports Theme.
      [`${basic}/src/Likes.res`]: [sheetId(`${basic}/src/Theme.res`)],
      // Widget's own styles, in the dependency.
      [`${widgets}/src/Widget.res`]: [sheetId(`${widgets}/src/Widget.res`)],
    });
  });

  test("puts a file's imports' sheets before its own, and each once, through cycles", () => {
    const scanned = scan(copyFixture('basic'));
    const likes = [...scanned.files.values()].find(({id}) =>
      id.endsWith('/Likes.res'),
    )!;
    // Two style files beside it, importing each other; and one it imports only dynamically.
    const [a, b, c] = ['a', 'b', 'c'].map((name) =>
      join(dirname(likes.file), `${name}.res.js`),
    );
    const files = new Map([[likes.file, likes]]);
    for (const [file, sheet] of [
      [a!, 'waaaaaa'],
      [b!, 'wbbbbbb'],
      [c!, 'wcccccc'],
    ] as const) {
      files.set(file, {id: file, file, kind: 'shared', rpcs: [], sheet});
    }
    const code: Record<string, string> = {
      [likes.file]: `'use weft entrypoint'\nimport * as A from "./a.res.js";\nimport("./c.res.js");\n`,
      [a!]: `import * as B from "./b.res.js";\nexport * from "./a.res.js";\n`,
      [b!]: `import * as A from "./a.res.js";\n`,
    };
    const sheets = entrypointSheets(
      {...scanned, files},
      (file) => code[file] ?? '',
    );
    expect(sheets[likes.id]).toEqual(['wbbbbbb', 'waaaaaa']);
  });
});
