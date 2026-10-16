// Module resolution hooks for benchmark processes (see `register.mjs`).
//
// A benchmark bundle leaves `mitata` external (see any benchmark package's
// vite.config.ts), so this one import is where results can be captured without
// the bundle's cooperation. That matters for `res-bench compare`, which runs
// bundles built from earlier commits as they were. It also means every bundle
// runs against this package's mitata, wherever the bundle sits on disk, so both
// sides of a comparison are measured by the same harness.

const shim = new URL('./mitata.mjs', import.meta.url).href;

export async function resolve(specifier, context, nextResolve) {
  // The shim's own `import 'mitata'` must reach the real thing.
  if (specifier === 'mitata' && context.parentURL !== shim) {
    return {url: shim, shortCircuit: true};
  }
  return nextResolve(specifier, context);
}
