/** Recordings built by hand, for the tests. */
import type {Measurement, Recording} from './results.ts';

export const measurement = (
  name: string,
  avg: number,
  group?: string,
): Measurement => ({
  name,
  ...(group === undefined ? {} : {group}),
  avg,
  min: avg,
  p50: avg,
  p75: avg,
  p99: avg,
  max: avg,
  samples: 12,
});

export const recordingOf = (
  processes: Measurement[][],
  overrides: Partial<Recording> = {},
): Recording => ({
  version: 1,
  recordedAt: '2026-10-16T00:00:00.000Z',
  package: 'packages/example/benchmarks',
  entry: 'bench',
  filter: null,
  isolated: true,
  source: {label: 'working tree', commit: '0123456789abcdef', dirty: false},
  environment: {
    node: 'v24.0.0',
    v8: '13.0',
    platform: 'darwin',
    arch: 'arm64',
    cpu: 'Test CPU',
    cores: 8,
    memoryGiB: 16,
    onBattery: false,
    lowPowerMode: false,
    mitata: '1.0.34',
  },
  processes: processes.map((benchmarks) => ({benchmarks})),
  ...overrides,
});

/**
 * An isolated recording: each benchmark in processes of its own, one per time
 * in `times`. A benchmark named `<implementation>.<group>` is given `group`, as
 * `Comparison` registers them.
 */
export const isolated = (
  benchmarks: {name: string; group?: string; times: number[]}[],
  overrides: Partial<Recording> = {},
): Recording =>
  recordingOf(
    benchmarks.flatMap(({name, group, times}) =>
      times.map((time) => [measurement(name, time, group)]),
    ),
    overrides,
  );
