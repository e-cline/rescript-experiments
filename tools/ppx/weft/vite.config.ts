import {defineConfig} from 'vite-plus';

import {opamExec, ppxSetupTask} from '../../../vite.config.base.ts';

export default defineConfig({
  run: {
    tasks: {
      // Builds the PPX executable (`_build/default/ppx_src/bin/main.exe`, which
      // `./ppx` forwards to) with dune, from the opam switch the root
      // `ppx:setup` task makes sure exists and matches the lock file (see
      // ../README.md). The root-level `res` task depends on this: any package
      // listing the PPX in its `ppx-flags` needs the executable to exist
      // before `rescript build` compiles it. Not cached -- dune is already
      // incremental, and a cache replay wouldn't restore `_build`.
      build: {
        command: `${opamExec} dune build`,
        dependsOn: [ppxSetupTask],
        cache: false,
      },
      cleanbuild: {
        command: `${opamExec} dune clean`,
        cache: false,
      },
    },
  },
});
