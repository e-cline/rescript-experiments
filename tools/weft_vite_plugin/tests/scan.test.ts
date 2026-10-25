import {cpSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

import {afterAll, describe, expect, test} from 'vite-plus/test';

import {
  entrypoints,
  fileId,
  findPackages,
  hasPpx,
  markedFileIds,
  readCompiledFile,
  scan,
  sheetId,
  styleFiles,
  styleNames,
} from '../src/internal/scan.js';
import {copyFixture, fixtureName, fixtures, removeCopies} from './support.js';

afterAll(removeCopies);

const basic = fixtureName('basic');
const widgets = fixtureName('widgets');

/** Rewrites the `rescript.json` at `root`, changing the fields in `change`. */
function changeRescriptJson(root: string, change: Record<string, unknown>) {
  const path = join(root, 'rescript.json');
  const config = JSON.parse(readFileSync(path, 'utf8'));
  writeFileSync(path, JSON.stringify({...config, ...change}));
}

describe('scan', () => {
  const root = copyFixture('basic');
  const scanned = scan(root);

  test('finds the app and its ReScript dependencies, transitively', () => {
    const packages = new Map(
      findPackages(root).map((pkg) => [pkg.name, pkg.dir]),
    );
    expect(packages.get(basic)).toBe(root);
    expect(packages.get(widgets)).toBe(join(fixtures, 'widgets'));
    // Dependencies of dependencies: weft's own.
    expect(packages.has('@e-cline/weft')).toBe(true);
    // Not dev dependencies.
    expect(packages.has('rescript-vitest')).toBe(false);
  });

  test('finds exactly the entrypoint files, by the ids the PPX gave them', () => {
    expect(entrypoints(scanned).map(({id, file}) => [id, file])).toEqual([
      [`${basic}/src/Later.res`, join(root, 'src/Later.res.js')],
      [`${basic}/src/Likes.res`, join(root, 'src/Likes.res.js')],
      [`${basic}/src/Panels.res`, join(root, 'src/Panels.res.js')],
      [`${basic}/src/nested/Deep.res`, join(root, 'src/nested/Deep.res.js')],
      [
        `${widgets}/src/Widget.res`,
        join(fixtures, 'widgets/src/Widget.res.js'),
      ],
    ]);
  });

  test('also knows the server files, and leaves out dev sources and other files', () => {
    const files = [...scanned.files.values()].map(({file, kind}) => [
      file,
      kind,
    ]);
    expect(files).toContainEqual([join(root, 'src/Notes.res.js'), 'server']);
    const paths = files.map(([file]) => file);
    // Compiled through the PPX, with the directive, but in a dev source.
    expect(paths).not.toContain(join(root, 'tests/Fake.res.js'));
    expect(paths).not.toContain(join(root, 'src/NotReScript.js'));
    // The fixtures' own: the app's and the dependency's.
    const own = [...scanned.files.values()].filter(
      ({id}) => id.startsWith(basic) || id.startsWith(widgets),
    );
    // (Theme, with styles and no other directive, is one.)
    expect(own).toHaveLength(8);
    // And weft_server's own server-only modules, which an app's client mustn't import either.
    expect(
      [...scanned.files.values()]
        .filter(({id}) => id.startsWith('@e-cline/weft_server/'))
        .map(({id, kind}) => [id, kind])
        .sort(([a], [b]) => (a! < b! ? -1 : 1)),
    ).toEqual([
      ['@e-cline/weft_server/src/server/Page.res', 'server'],
      ['@e-cline/weft_server/src/server/Render.res', 'server'],
      ['@e-cline/weft_server/src/server/RpcServer.res', 'server'],
    ]);
  });

  test("collects the RPCs' IDs, the app's and its dependencies', with the files declaring them", () => {
    expect(
      [...scanned.rpcs]
        .map(([id, file]) => [id, file.id])
        .sort(([a], [b]) => (a! < b! ? -1 : 1)),
    ).toEqual([
      ['basic.remove', `${basic}/src/Api.res`],
      ['basic.save', `${basic}/src/Api.res`],
      ['widgets.press', `${widgets}/src/Widget.res`],
    ]);
    expect(scanned.files.get(join(root, 'src/Api.res.js'))?.kind).toBe(
      'shared',
    );
  });

  test('knows the PPX is set up', () => {
    expect(hasPpx(root)).toBe(true);
  });
});

describe('file ids', () => {
  const root = copyFixture('basic');
  const [app] = findPackages(root);

  test("are the package's name and the source's path", () => {
    expect(fileId(app!, join(root, 'src/nested/Deep.res.js'), '.res.js')).toBe(
      `${basic}/src/nested/Deep.res`,
    );
    expect(fileId(app!, join(root, 'src/Deep.mjs'), '.mjs')).toBe(
      `${basic}/src/Deep.res`,
    );
  });

  test('are read from the marks the PPX wrote', () => {
    const panels = readFileSync(join(root, 'src/Panels.res.js'), 'utf8');
    expect(markedFileIds(panels)).toEqual([`${basic}/src/Panels.res`]);
  });

  test('that differ from the marks are an error', () => {
    // A compiled file moved without being compiled again.
    const likes = readFileSync(join(root, 'src/Likes.res.js'), 'utf8');
    const moved = join(root, 'src/Moved.res.js');
    expect(() => readCompiledFile(app!, moved, '.res.js', likes)).toThrow(
      `marks an entrypoint as being in ${basic}/src/Likes.res, but its id is ${basic}/src/Moved.res`,
    );
  });
});

describe('the scan', () => {
  const ids = (root: string) =>
    entrypoints(scan(root))
      .map(({id}) => id)
      .filter((id) => id.startsWith(basic));

  test('follows `subdirs`: none, or a list', () => {
    const root = copyFixture('basic');
    changeRescriptJson(root, {sources: {dir: 'src'}});
    expect(ids(root)).not.toContain(`${basic}/src/nested/Deep.res`);
    // A directory the list leaves out: had the scan read it, the misplaced file would have failed.
    mkdirSync(join(root, 'src/other'));
    cpSync(
      join(root, 'src/Likes.res.js'),
      join(root, 'src/other/Likes.res.js'),
    );
    changeRescriptJson(root, {
      sources: [{dir: 'src', subdirs: [{dir: 'nested'}]}],
    });
    expect(ids(root)).toContain(`${basic}/src/nested/Deep.res`);
  });

  test('fails on an RPC ID declared twice, naming both files', () => {
    const root = copyFixture('basic');
    cpSync(join(root, 'src/Api.res.js'), join(root, 'src/nested/Again.res.js'));
    expect(() => scan(root)).toThrow(
      `[weft] the RPC ID basic.save is declared twice: in ${basic}/src/Api.res and in ${basic}/src/nested/Again.res.`,
    );
  });

  test("knows when the PPX isn't set up", () => {
    const root = copyFixture('basic');
    changeRescriptJson(root, {'ppx-flags': []});
    expect(hasPpx(root)).toBe(false);
  });

  test('fails on a dependency it cannot find', () => {
    const root = copyFixture('basic');
    changeRescriptJson(root, {dependencies: ['@e-cline/missing']});
    expect(() => scan(root)).toThrow(
      /couldn't find @e-cline\/missing, a dependency in/,
    );
  });
});

describe('style files', () => {
  test("have the sheet id the PPX's names end in, the app's and the dependency's", () => {
    const root = copyFixture('basic');
    const scanned = scan(root);
    expect(styleFiles(scanned).map(({id, sheet}) => [id, sheet])).toEqual(
      [
        `${basic}/src/Notes.res`,
        `${basic}/src/Theme.res`,
        `${widgets}/src/Widget.res`,
      ].map((id) => [id, sheetId(id)]),
    );
    const theme = readFileSync(join(root, 'src/Theme.res.js'), 'utf8');
    const sheet = sheetId(`${basic}/src/Theme.res`);
    expect(styleNames(theme)).toEqual([
      `--Theme-ink_${sheet}`,
      `Theme-global0_${sheet}`,
      `Theme-badge_${sheet}`,
    ]);
  });

  test('sheet ids are the same hash as weft_css and ppx_weft', () => {
    // As pinned in weft_css's SheetId tests (and the PPX's, through its fixtures).
    expect(sheetId('spike-res/src/Button.res')).toBe('wnscs2w');
    expect(sheetId('a/src/Ä.res')).toBe('wh00nt5');
  });

  test('whose names have another sheet id are an error', () => {
    const root = copyFixture('basic');
    const file = join(root, 'src/Theme.res.js');
    writeFileSync(
      file,
      readFileSync(file, 'utf8').replace('Theme-badge_w', 'Theme-badge_x'),
    );
    expect(() => scan(root)).toThrow(
      /has a style named Theme-badge_x\w+, but its sheet id is w\w+ \(from its id, .*src\/Theme\.res\)/,
    );
  });

  test('with the same sheet id are an error, naming both', () => {
    const scanned = scan(copyFixture('basic'));
    const [first, second] = styleFiles(scanned);
    scanned.files.set(second!.file, {...second!, sheet: first!.sheet});
    expect(() => styleFiles(scanned)).toThrow(
      `[weft] ${first!.id} and ${second!.id} have the same sheet id, ${first!.sheet}: rename one of them.`,
    );
  });
});
