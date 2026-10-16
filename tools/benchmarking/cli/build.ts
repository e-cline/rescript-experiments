/**
 * Finding the code to measure: the working tree's own bundle, or a bundle built
 * from a commit.
 *
 * A benchmark bundle is self-contained apart from mitata (which `capture/`
 * supplies), so a bundle built from any commit runs from anywhere. Each is
 * built once, in a temporary git worktree, and kept under
 * `.bench/builds/<commit>/` for the next comparison that needs it.
 */
import {execFileSync, spawnSync} from 'node:child_process';
import {
  cpSync,
  existsSync,
  mkdtempSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

import type {Source} from './results.ts';

export const git = (args: string[], cwd: string): string =>
  execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();

/** A built benchmark package's `dist/`, and what it was built from. */
export type Build = {directory: string; source: Source};

/**
 * What to remove when `res-bench` exits, however it exits, so that a Ctrl-C
 * partway through a build doesn't leave a worktree behind.
 */
export const cleanups = new Set<() => void>();

/**
 * A copy of the working tree's `dist/` (built by the task that runs this), so
 * that rebuilding while a comparison runs doesn't change what it measures.
 */
export const workingTreeBuild = (
  repoRoot: string,
  packageDirectory: string,
): Build => {
  const dist = join(packageDirectory, 'dist');
  if (!existsSync(dist)) {
    throw new Error(`${dist} doesn't exist. Build the package first.`);
  }
  const directory = mkdtempSync(join(tmpdir(), 'res-bench-working-'));
  cpSync(dist, directory, {recursive: true});
  cleanups.add(() => rmSync(directory, {recursive: true, force: true}));
  return {
    directory,
    source: {
      label: 'working tree',
      commit: git(['rev-parse', 'HEAD'], repoRoot),
      dirty: git(['status', '--porcelain'], repoRoot) !== '',
    },
  };
};

/** Runs `command` in `cwd`, appending its output to `log`; throws if it fails. */
const step = (command: string, args: string[], cwd: string, log: string) => {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8'});
  writeFileSync(
    log,
    `$ ${command} ${args.join(' ')}\n${result.stdout ?? ''}${result.stderr ?? ''}\n`,
    {flag: 'a'},
  );
  if (result.status !== 0) {
    throw new Error(
      `\`${command} ${args.join(' ')}\` failed (output in ${log}):\n` +
        `${result.stdout ?? ''}${result.stderr ?? result.error?.message ?? ''}`
          .trimEnd()
          .split('\n')
          .slice(-20)
          .join('\n'),
    );
  }
};

/**
 * The package at `packagePath` (relative to the repository root), built from
 * `ref`. Reuses an earlier build of the same commit.
 */
export const refBuild = (
  repoRoot: string,
  packagePath: string,
  ref: string,
): Build => {
  let commit: string;
  try {
    commit = git(['rev-parse', '--verify', `${ref}^{commit}`], repoRoot);
  } catch {
    throw new Error(`${ref} isn't a commit git knows.`);
  }
  const source = {label: ref, commit, dirty: false};
  const cached = join(repoRoot, '.bench', 'builds', commit, packagePath);
  if (existsSync(cached)) {
    return {directory: cached, source};
  }

  console.log(
    `Building ${packagePath} at ${ref} (${commit.slice(0, 7)}) in a temporary worktree. This happens once per commit.`,
  );
  const worktree = mkdtempSync(join(tmpdir(), 'res-bench-worktree-'));
  const log = `${worktree}.log`;
  const remove = () => {
    try {
      git(['worktree', 'remove', '--force', worktree], repoRoot);
    } catch {
      rmSync(worktree, {recursive: true, force: true});
      git(['worktree', 'prune'], repoRoot);
    }
  };
  cleanups.add(remove);
  try {
    git(['worktree', 'add', '--detach', worktree, commit], repoRoot);
    const packageDirectory = join(worktree, packagePath);
    if (!existsSync(packageDirectory)) {
      throw new Error(`${packagePath} doesn't exist at ${ref}.`);
    }
    step(
      'pnpm',
      ['install', '--frozen-lockfile', '--prefer-offline'],
      worktree,
      log,
    );
    step('pnpm', ['exec', 'vp', 'run', 'build'], packageDirectory, log);
    // Copied under a temporary name and then renamed, so that an interrupted
    // copy never looks like a finished build.
    const partial = `${cached}.partial-${process.pid}`;
    cpSync(join(packageDirectory, 'dist'), partial, {recursive: true});
    renameSync(partial, cached);
    rmSync(log, {force: true});
  } finally {
    remove();
    cleanups.delete(remove);
  }
  return {directory: cached, source};
};
