import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {after, before, describe, it} from 'node:test';

import {measurement, recordingOf} from './fixtures.ts';
import {
  averagesByName,
  benchmarkNames,
  errors,
  exactly,
  identities,
  measureProcess,
} from './results.ts';

describe('identities', () => {
  const identity = (name: string, group?: string) =>
    identities(recordingOf([[measurement(name, 1, group)]])).get(name);

  it('reads the implementation off a name that ends with its group', () => {
    assert.deepEqual(identity('Belt.Map.get n=1000', 'get n=1000'), {
      name: 'Belt.Map.get n=1000',
      group: 'get n=1000',
      implementation: 'Belt.Map',
      operation: 'get',
      parameter: 'n=1000',
      size: 1000,
    });
  });

  it('keeps the whole group as the operation when it has no parameter', () => {
    const {operation, parameter, size} = identity(
      'BTree.diff (10 overwrites)',
      'diff (10 overwrites)',
    )!;
    assert.equal(operation, 'diff (10 overwrites)');
    assert.equal(parameter, undefined);
    assert.equal(size, undefined);
  });

  it('gives no size for a parameter that is not a number', () => {
    const {parameter, size} = identity('A.mode kind=fast', 'mode kind=fast')!;
    assert.equal(parameter, 'kind=fast');
    assert.equal(size, undefined);
  });

  it("gives no implementation when the name doesn't end with the group", () => {
    assert.deepEqual(identity('write one atom (idle)', 'one computed'), {
      name: 'write one atom (idle)',
      group: 'one computed',
    });
  });

  it('gives no implementation without a group', () => {
    assert.deepEqual(identity('BTree.get n=1000'), {
      name: 'BTree.get n=1000',
      group: undefined,
    });
  });
});

describe('exactly', () => {
  for (const name of ['set (build) n=1000', 'a.b*c+d?', 'x^y$z [1] {2} |\\']) {
    it(`selects ${JSON.stringify(name)} and nothing else`, () => {
      const pattern = new RegExp(exactly(name));
      assert.ok(pattern.test(name));
      assert.ok(!pattern.test(`${name} `));
      assert.ok(!pattern.test(`x${name}`));
    });
  }
});

describe('averagesByName', () => {
  it("collects each benchmark's averages across processes, in order", () => {
    const recording = recordingOf([
      [measurement('a', 1), measurement('b', 10)],
      [measurement('a', 2)],
      [measurement('b', 20)],
    ]);
    assert.deepEqual(
      [...averagesByName(recording)],
      [
        ['a', [1, 2]],
        ['b', [10, 20]],
      ],
    );
  });
});

describe('errors', () => {
  it('lists each distinct error once', () => {
    const failed = {name: 'broken', error: 'boom'};
    const recording = recordingOf([[measurement('a', 1)]]);
    recording.processes.push({benchmarks: [failed]}, {benchmarks: [failed]});
    assert.deepEqual(errors(recording), ['broken: boom']);
  });
});

// A benchmark program as small as one can be, run through the module hook
// that captures what mitata measures. It imports `mitata` from a directory
// with no `node_modules`, as a bundle built from an earlier commit and kept
// under `.bench/builds/` does.
describe('capturing a benchmark program', () => {
  let directory: string;
  let program: string;

  before(() => {
    directory = mkdtempSync(join(tmpdir(), 'res-bench-test-'));
    program = join(directory, 'bench.js');
    writeFileSync(
      program,
      `import {bench, do_not_optimize, group, run} from 'mitata';
group('get n=10', () => {
  bench('A.get n=10', () => do_not_optimize(1 + 1));
  bench('B.get n=10', () => do_not_optimize(2 + 2));
});
bench('ungrouped', () => do_not_optimize(3));
const pattern = process.argv[2];
await run(pattern === undefined ? {} : {filter: new RegExp(pattern)});
`,
    );
  });

  after(() => rmSync(directory, {recursive: true, force: true}));

  it("lists the program's benchmarks without measuring them", async () => {
    assert.deepEqual(await benchmarkNames(program), [
      'A.get n=10',
      'B.get n=10',
      'ungrouped',
    ]);
  });

  it('measures only what the filter selects, with its group', async () => {
    const {benchmarks} = await measureProcess(program, exactly('B.get n=10'));
    assert.equal(benchmarks.length, 1);
    const [result] = benchmarks;
    assert.ok(result !== undefined && 'avg' in result);
    assert.equal(result.name, 'B.get n=10');
    assert.equal(result.group, 'get n=10');
    assert.ok(result.avg > 0 && result.samples > 0);
  });

  it('records no group for a benchmark outside one', async () => {
    const {benchmarks} = await measureProcess(program, exactly('ungrouped'));
    assert.equal(benchmarks[0]?.name, 'ungrouped');
    assert.equal(
      benchmarks[0] !== undefined && 'group' in benchmarks[0]
        ? benchmarks[0].group
        : undefined,
      undefined,
    );
  });

  it('reports a program that fails, with what it printed', async () => {
    const failing = join(directory, 'failing.js');
    writeFileSync(failing, "throw new Error('setup went wrong');\n");
    await assert.rejects(measureProcess(failing, null), /setup went wrong/);
  });

  it("reports a program that never calls mitata's run", async () => {
    const silent = join(directory, 'silent.js');
    writeFileSync(
      silent,
      "import {bench} from 'mitata';\nbench('x', () => {});\n",
    );
    await assert.rejects(measureProcess(silent, null), /without recording/);
  });
});
