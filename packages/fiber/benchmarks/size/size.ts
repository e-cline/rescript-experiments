// Measures what fiber and fiber_dom add to a production bundle: each
// entry below is bundled by Vite on its own, minified by Terser until another
// pass stops shrinking it, and compressed with gzip and brotli at their
// highest levels. Run with `vp run size` (see ../README.md).

import * as assert from 'node:assert/strict';
import * as path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as zlib from 'node:zlib';

import {minify, type MinifyOptions} from 'terser';
import {build, type Rollup} from 'vite';

const here = path.dirname(fileURLToPath(import.meta.url));

// Vite resolves `@e-cline/js_env`'s `production` export condition (which
// `Common.Env.isDev` reads) from this, not from `mode`, so a `NODE_ENV`
// left set in the shell would otherwise measure a development build.
process.env.NODE_ENV = 'production';

type Entry = {
  name: string;
  /** A module the root `res` task compiles. */
  file: string;
  /** The `console.` calls the entry makes itself, rather than the libraries. */
  consoleCalls: number;
};

const entries: Entry[] = [
  {name: 'counter', file: 'Counter.res.js', consoleCalls: 0},
  {name: 'full API', file: 'FullApi.res.js', consoleCalls: 0},
  {
    name: 'todo app (examples/fiber_app)',
    file: '../../../../examples/fiber_app/src/Main.res.js',
    // `Main.res` logs an error when the page has no `#app` element.
    consoleCalls: 1,
  },
];

const terserOptions: MinifyOptions = {
  module: true,
  toplevel: true,
  ecma: 2020,
  compress: {passes: 3},
  mangle: true,
  format: {comments: false},
};

/** `file` and everything it imports, as one unminified ES module. */
async function bundle(file: string): Promise<string> {
  const output = await build({
    configFile: false,
    logLevel: 'silent',
    mode: 'production',
    define: {'process.env.NODE_ENV': '"production"'},
    build: {
      minify: false,
      write: false,
      rolldownOptions: {
        input: path.resolve(here, file),
        output: {format: 'es', codeSplitting: false},
      },
    },
  });
  const outputs = (
    Array.isArray(output) ? output : [output]
  ) as Rollup.RollupOutput[];
  const chunks = outputs
    .flatMap((result) => result.output)
    .filter((item): item is Rollup.OutputChunk => item.type === 'chunk');
  assert.equal(chunks.length, 1, `${file}: expected a single chunk`);
  return chunks[0]!.code;
}

/** `code`, minified by Terser again and again until a pass doesn't shrink it. */
async function minifyFully(code: string): Promise<string> {
  for (;;) {
    const result = await minify(code, terserOptions);
    const next = result.code ?? '';
    if (next.length >= code.length) {
      return code;
    }
    code = next;
  }
}

/** Text from the key warnings' messages (see `KeyWarnings.res`). */
const devWarnings = ['two children with the same key', 'should have a unique'];

/**
 * Checks that development-only code, such as the key warnings (`KeyWarnings`,
 * behind `Common.Env.isDev`) and the full error messages (`Errors`, which
 * production builds replace with codes), was left out of the production bundle.
 */
function checkNoDevCode(entry: Entry, code: string) {
  const consoleCalls = code.match(/\bconsole\./g)?.length ?? 0;
  assert.equal(
    consoleCalls,
    entry.consoleCalls,
    `${entry.name}: ${consoleCalls} console calls in the minified bundle, ` +
      `expected ${entry.consoleCalls}; is development-only code included?`,
  );
  for (const warning of devWarnings) {
    assert.ok(
      !code.includes(warning),
      `${entry.name}: the minified bundle includes the warning "${warning}"`,
    );
  }
  // Every error message starts with "Fiber: "; their codes replace them.
  assert.ok(
    !code.includes('Fiber: '),
    `${entry.name}: the minified bundle includes a development error message`,
  );
  assert.ok(
    code.includes('Fiber error '),
    `${entry.name}: the minified bundle has no production error message`,
  );
}

const rows: string[][] = [];
for (const entry of entries) {
  const code = await minifyFully(await bundle(entry.file));
  checkNoDevCode(entry, code);
  const bytes = Buffer.from(code);
  const gzip = zlib.gzipSync(bytes, {level: 9});
  const brotli = zlib.brotliCompressSync(bytes, {
    params: {
      [zlib.constants.BROTLI_PARAM_QUALITY]: 11,
      [zlib.constants.BROTLI_PARAM_SIZE_HINT]: bytes.length,
    },
  });
  rows.push([
    entry.name,
    ...[bytes, gzip, brotli].map((data) => data.length.toLocaleString('en-US')),
  ]);
}

const header = ['', 'minified (B)', 'gzip (B)', 'brotli (B)'];
const widths = header.map((cell, i) =>
  Math.max(cell.length, ...rows.map((row) => row[i]!.length)),
);
for (const row of [header, ...rows]) {
  console.log(
    row
      .map((cell, i) =>
        i === 0 ? cell.padEnd(widths[i]!) : cell.padStart(widths[i]!),
      )
      .join('  '),
  );
}
