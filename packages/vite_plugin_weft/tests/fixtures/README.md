# Fixture apps

Small apps for the plugin's tests, whose "compiled ReScript" is written by hand: each `.res.js` file
is what `rescript build` with `ppx_weft` would write (the directive first, entrypoints marked with
their ids), so these tests need neither ReScript nor the PPX. `examples/weft_split` puts the real
compiler output through the plugin.

The tests copy a fixture to a temporary directory first, link its dependencies into a `node_modules`
there, and build or serve the copy.

- `basic/`: a server entry, server modules (one with a sentinel string that must never reach the
  client), entrypoints at the top level, in modules (one named `Error`) and in a subdirectory, a
  shared module two of them import, a large client-only module (with a sentinel of its own), an
  entrypoint in a dependency (`widgets/`), and files the scan must leave out: one in a dev source,
  and one without the suffix.
- `client-imports-server/`: client code that imports a server file through a shared one, which the
  plugin refuses.
