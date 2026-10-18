import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

import {afterAll, describe, expect, test} from 'vite-plus/test';

import type {CompiledFile} from '../src/internal/scan.js';
import {
  buildAssets,
  clientReferencesCode,
  devAssets,
  devUrl,
  type Manifest,
} from '../src/internal/virtualModules.js';

const files: CompiledFile[] = [
  {id: 'app/src/Likes.res', file: '/app/src/Likes.res.js', kind: 'entrypoint'},
  {
    id: 'lib/src/Widget.res',
    file: '/lib/src/Widget.res.js',
    kind: 'entrypoint',
  },
];

const dir = mkdtempSync(join(tmpdir(), 'weft-references-'));
let written = 0;

afterAll(() => {
  rmSync(dir, {recursive: true, force: true});
});

/** Runs the generated module, with each `import(path)` giving `{path}`. */
async function runReferences(code: string) {
  const file = join(dir, `references-${written++}.mjs`);
  writeFileSync(
    file,
    code.replace(/import\(("[^"]*")\)/g, 'Promise.resolve({path: $1})'),
  );
  return (await import(/* @vite-ignore */ pathToFileURL(file).href)) as {
    default: Record<string, () => Promise<{path: string}>>;
    loadModule: (id: string) => Promise<{path: string}>;
  };
}

describe('virtual:weft/client-references', () => {
  test('maps each entrypoint file to an import of it', async () => {
    const code = clientReferencesCode(files);
    expect(code).toContain(
      '"app/src/Likes.res": () => import("/app/src/Likes.res.js"),',
    );
    expect(code).toContain(
      '"lib/src/Widget.res": () => import("/lib/src/Widget.res.js"),',
    );
    const module = await runReferences(code);
    expect(Object.keys(module.default)).toEqual([
      'app/src/Likes.res',
      'lib/src/Widget.res',
    ]);
    expect(await module.loadModule('lib/src/Widget.res')).toEqual({
      path: '/lib/src/Widget.res.js',
    });
  });

  test("loads nothing that isn't in it", async () => {
    const module = await runReferences(clientReferencesCode(files));
    await expect(module.loadModule('app/src/Server.res')).rejects.toThrow(
      "[weft] app/src/Server.res isn't an entrypoint file",
    );
    await expect(module.loadModule('toString')).rejects.toThrow(
      "isn't an entrypoint file",
    );
    await expect(module.loadModule('__proto__')).rejects.toThrow(
      "isn't an entrypoint file",
    );
  });

  test('is empty without entrypoints', async () => {
    const module = await runReferences(clientReferencesCode([]));
    expect(module.default).toEqual({});
  });
});

describe('virtual:weft/assets', () => {
  test('in development: Vite client, the bootstrap, and each file as the dev server serves it', () => {
    expect(devAssets('/app', '/', '/app/src/Client.res.js', files)).toEqual({
      scripts: ['/@vite/client', '/src/Client.res.js'],
      preloads: [],
      styles: [],
      entrypoints: {
        'app/src/Likes.res': ['/src/Likes.res.js'],
        'lib/src/Widget.res': ['/@fs/lib/src/Widget.res.js'],
      },
    });
    expect(devUrl('/app', '/base/', '/app/src/X.res.js')).toBe(
      '/base/src/X.res.js',
    );
  });

  test("in a build: from the client's manifest, with what each chunk imports", () => {
    const manifest: Manifest = {
      'src/Client.res.js': {
        file: 'assets/client-a1.js',
        isEntry: true,
        imports: ['_runtime.js'],
        css: ['assets/client-a1.css'],
      },
      '_runtime.js': {file: 'assets/runtime-b2.js'},
      '_shared.js': {file: 'assets/shared-c3.js', imports: ['_runtime.js']},
      'src/Likes.res.js': {
        file: 'assets/Likes-d4.js',
        isDynamicEntry: true,
        imports: ['_shared.js'],
      },
      '../lib/src/Widget.res.js': {
        file: 'assets/Widget-e5.js',
        isDynamicEntry: true,
      },
    };
    expect(
      buildAssets(manifest, '/app', '/', '/app/src/Client.res.js', files),
    ).toEqual({
      scripts: ['/assets/client-a1.js'],
      preloads: ['/assets/runtime-b2.js'],
      styles: ['/assets/client-a1.css'],
      entrypoints: {
        'app/src/Likes.res': [
          '/assets/Likes-d4.js',
          '/assets/shared-c3.js',
          '/assets/runtime-b2.js',
        ],
        'lib/src/Widget.res': ['/assets/Widget-e5.js'],
      },
    });
  });

  test('a file missing from the manifest is an error', () => {
    expect(() =>
      buildAssets({}, '/app', '/', '/app/src/Client.res.js', []),
    ).toThrow('[weft] the client build has no chunk for src/Client.res.js');
  });
});
