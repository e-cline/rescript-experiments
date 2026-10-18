import {mkdirSync, writeFileSync} from 'node:fs';
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
} from '../src/internal/scan.js';
import {copyFixture, removeCopies} from './support.js';

afterAll(removeCopies);

describe('scan', () => {
  const root = copyFixture('basic');
  const scanned = scan(root);

  test('finds the app and its ReScript dependencies', () => {
    expect(findPackages(root).map((pkg) => [pkg.name, pkg.dir])).toEqual([
      ['@fixtures/basic', root],
      ['@fixtures/widgets', join(root, 'widgets')],
    ]);
  });

  test('finds exactly the entrypoint files, by the ids the PPX gives them', () => {
    expect(entrypoints(scanned).map(({id, file}) => [id, file])).toEqual([
      ['@fixtures/basic/src/Likes.res', join(root, 'src/Likes.res.js')],
      ['@fixtures/basic/src/Panels.res', join(root, 'src/Panels.res.js')],
      [
        '@fixtures/basic/src/nested/Deep.res',
        join(root, 'src/nested/Deep.res.js'),
      ],
      [
        '@fixtures/widgets/src/Widget.res',
        join(root, 'widgets/src/Widget.res.js'),
      ],
    ]);
  });

  test('also knows the server files, and leaves out dev sources and other files', () => {
    const files = [...scanned.files.values()].map(({file, kind}) => [
      file,
      kind,
    ]);
    expect(files).toContainEqual([join(root, 'src/Server.res.js'), 'server']);
    expect(files).toContainEqual([join(root, 'src/Notes.res.js'), 'server']);
    expect(files.map(([file]) => file)).not.toContain(
      join(root, 'tests/Fake.res.js'),
    );
    expect(files.map(([file]) => file)).not.toContain(
      join(root, 'src/Plain.js'),
    );
    expect(scanned.files.size).toBe(6);
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
      '@fixtures/basic/src/nested/Deep.res',
    );
    expect(fileId(app!, join(root, 'src/Deep.mjs'), '.mjs')).toBe(
      '@fixtures/basic/src/Deep.res',
    );
  });

  test('are read from the marks too', () => {
    expect(
      markedFileIds(
        'A$B.mark(A, "pkg/src/A.res#");\nEntrypoint$WeftCore.mark(A$Nested, "pkg/src/A.res#Nested");\n',
      ),
    ).toEqual(['pkg/src/A.res']);
  });

  test('that differ from the marks are an error', () => {
    const file = join(root, 'src/Moved.res.js');
    const code =
      '\'use weft entrypoint\'\nM.mark(Moved, "@fixtures/basic/src/Elsewhere.res#");\n';
    expect(() => readCompiledFile(app!, file, '.res.js', code)).toThrow(
      /marks an entrypoint as being in @fixtures\/basic\/src\/Elsewhere\.res, but its id is @fixtures\/basic\/src\/Moved\.res/,
    );
  });
});

describe('the scan', () => {
  test('follows subdirectory lists, and files coming and going', () => {
    const root = copyFixture('basic');
    writeFileSync(
      join(root, 'rescript.json'),
      JSON.stringify({
        name: '@fixtures/basic',
        sources: [{dir: 'src', subdirs: [{dir: 'nested'}]}],
        suffix: '.res.js',
      }),
    );
    mkdirSync(join(root, 'src/other'));
    writeFileSync(
      join(root, 'src/other/Skipped.res.js'),
      "'use weft entrypoint'\n",
    );
    const ids = entrypoints(scan(root)).map(({id}) => id);
    expect(ids).toEqual([
      '@fixtures/basic/src/Likes.res',
      '@fixtures/basic/src/Panels.res',
      '@fixtures/basic/src/nested/Deep.res',
    ]);
    expect(hasPpx(root)).toBe(false);
  });

  test('fails on a dependency it cannot find', () => {
    const root = copyFixture('basic');
    writeFileSync(
      join(root, 'rescript.json'),
      JSON.stringify({
        name: '@fixtures/basic',
        sources: 'src',
        dependencies: ['@fixtures/missing'],
      }),
    );
    expect(() => scan(root)).toThrow(
      /couldn't find @fixtures\/missing, a dependency in/,
    );
  });
});
