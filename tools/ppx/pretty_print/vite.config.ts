import {defineConfig} from 'vite-plus';

export default defineConfig({
  run: {
    tasks: {
      // Builds the PPX executable (`_build/default/ppx_src/bin/main.exe`, which
      // `./ppx` forwards to) with dune. `setup.sh` first makes sure the local
      // opam switch dune runs from exists and matches the lock file -- a
      // no-op except on a fresh clone or after the lock file changes. The root-level `res` task depends on this: any package
      // listing the PPX in its `ppx-flags` needs the executable to exist
      // before `rescript build` compiles it. Not cached -- dune is already
      // incremental, and a cache replay wouldn't restore `_build`.
      build: {
        command: ['./setup.sh', 'opam exec -- dune build'],
        cache: false,
      },
      cleanbuild: {
        command: 'opam exec -- dune clean',
        cache: false,
      },
    },
  },
});
