// Loaded with `node --import` into every benchmark process `res-bench` starts,
// where it hands the benchmark bundle `mitata.mjs` in place of mitata itself.
//
// A benchmark bundle leaves `mitata` external (see any benchmark package's
// vite.config.ts), so this one import is where results can be captured without
// the bundle's cooperation. That matters for `res-bench compare`, which runs
// bundles built from earlier commits as they were. It also means every bundle
// runs against this package's mitata, wherever the bundle sits on disk, so both
// sides of a comparison are measured by the same harness.
//
// `registerHooks` runs the hook in this thread. `register`, which this used
// before, starts a worker thread for its hooks, and that cost about 40 ms on
// every process: more than half of starting one.
import {registerHooks} from 'node:module';

const shim = new URL('./mitata.mjs', import.meta.url).href;

registerHooks({
  resolve(specifier, context, nextResolve) {
    // The shim's own `import 'mitata'` must reach the real thing.
    if (specifier === 'mitata' && context.parentURL !== shim) {
      return {url: shim, shortCircuit: true};
    }
    return nextResolve(specifier, context);
  },
});
