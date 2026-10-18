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
- `Chart`: one only `/other` uses, with a large module (`BigTable`) nothing else imports.

The server components are in [`src/Pages.res`](src/Pages.res), and use a server-only module,
[`src/Secrets.res`](src/Secrets.res). [`src/Server.res`](src/Server.res) is the server entry (an
`@e-cline/servy` app), and [`src/Client.res`](src/Client.res) the bootstrap.

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
entrypoint but `Chart`, and `/other` only `Chart` and `Counter`.
