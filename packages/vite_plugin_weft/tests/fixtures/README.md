# Fixture apps

Small apps for the plugin's tests. Each is a ReScript package in the workspace, listed in the root
`rescript.json`, so the root `res` task compiles it through `ppx_weft` like any other package, and
its `.res.js` output is committed with it. Nothing here is compiled by hand: a change to the PPX or
the compiler shows up in these files, and the tests run against what they really write.

The tests copy a fixture to a temporary directory (without its `node_modules`, which the copy links
to the same packages instead), and build it there or change its files, as `rescript build -w` would:
writing a compiled file again, taking one away, or putting it back.

- `basic/`: a server entry, a server file (`Notes`, with a sentinel string that must never reach the
  client), entrypoints at the top level, in modules (one named `Error`) and in a subdirectory, a
  module two of them share, a large client-only module (with a sentinel of its own), an entrypoint
  (`Later`) the dev tests take away and put back, an entrypoint in a dev source and a JavaScript
  file with the directive (neither of which the scan may pick up), and an entrypoint in a ReScript
  dependency, `widgets/`.
- `widgets/`: that dependency.
- `client_imports_server/`: client code that imports a server file through a shared one, which the
  plugin refuses.
