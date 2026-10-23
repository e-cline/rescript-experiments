# weft_split

Code-splitting with [Weft's server components](../../packages/weft_server), compiled by the real
ReScript and [`ppx_weft`](../../tools/ppx/weft), and bundled by
[`@e-cline/vite_plugin_weft`](../../packages/vite_plugin_weft). Its entrypoints come in every shape
the plugin has to handle:

- `Counter`: a file-level entrypoint (the file's own `make`), with state;
- `Widgets.Toggle` and `Widgets.Error`: entrypoints in modules, the second exported by ReScript as
  `$$Error`;
- `Fancy` and `Plain`: two entrypoints sharing a module (`Format`);
- `Outer`: an entrypoint rendering another (`Counter`) itself;
- `Chart`: one only `/other` uses, with a large module (`BigTable`) nothing else imports;
- `Link`: a link that navigates in place, on every page.

The server components are in [`src/Pages.res`](src/Pages.res), and use a server-only module,
[`src/Secrets.res`](src/Secrets.res). [`src/Server.res`](src/Server.res) is the server entry, an
`@e-cline/servy` app whose routes answer with `WeftServer.Page.respond`: the HTML page with the
payload streamed into it, or the bare payload when the client asks for it. The bootstrap is the
plugin's default one.

Run it:

```bash
pnpm --filter @e-cline/weft_split_example exec vp run dev
```

or build it and serve the build:

```bash
pnpm --filter @e-cline/weft_split_example exec vp run start
```

In `dev`, change `Secrets.res` while `rescript build -w` runs (`vp run -w res:watch`): the page
refetches its payload, and the counters keep their counts.

[`tests/Build_test.res`](tests/Build_test.res) builds the app and checks what came out: each
entrypoint file is a chunk of its own, `Format` is in a chunk `Fancy`'s and `Plain`'s both import,
`BigTable` is only in `Chart`'s, and nothing of the server's is in the client. Then it asks the
built server for each page's payload, and decodes it with the built chunks: `/` loads every
entrypoint but `Chart`, and `/other` only `Chart`, `Counter` and `Link`.

[`tests/Source_test.res`](tests/Source_test.res) and [`tests/Built_test.res`](tests/Built_test.res)
open the pages through [the plugin's harness](../../packages/vite_plugin_weft#testing-an-app), from
the sources and from a build: every entrypoint renders and works, a link navigates in place (the
counter, in the same place on both pages, keeps its count), and, from the sources, the chart's file
is loaded only once a page needs it. A difference between development and the build shows up as one
passing and the other failing.
