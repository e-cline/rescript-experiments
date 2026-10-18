# @e-cline/http_server_example

An example HTTP server built with [`@e-cline/server`](../../packages/server), this workspace's small
framework over the Web-standard `Request` and `Response`. It shows routes declared with paths as
lists of segments, HTML, text, JSON and streamed responses, a store shared between requests, and an
auth middleware, with both attached to the request under typed keys. The whole application is put
together as one pipe, from the outside in: middleware first, routes last.

- `src/Routes.res` -- the handlers, the routes, the auth middleware, and the application.
- `src/Notes.res` -- an in-memory stand-in for a database, shared by every request.
- `src/Main.res` -- starts the server.
- `serve.mjs` -- starts the same server from JavaScript.
- `tests/Routes_test.res` -- tests of the routes. They call the application directly with a
  `Request`, with no server running.
- `tests/EntryPoints_test.res` -- starts `src/Main.res` and `serve.mjs` as they'd be run, and calls
  each over HTTP.

| Method | Path           | Response                                                 |
| ------ | -------------- | -------------------------------------------------------- |
| GET    | `/`            | HTML: a page listing the routes                          |
| GET    | `/hello`       | Text: a greeting, to `?name=` if given                   |
| GET    | `/hello/:name` | Text: the same, with the name as a path parameter        |
| GET    | `/time`        | JSON: the current time                                   |
| POST   | `/echo`        | The request body, with the content type it was sent with |
| GET    | `/events`      | A streamed response: one JSON object per line (NDJSON)   |
| any    | `/inspect`     | JSON: the request's method, URL, query, headers and body |
| GET    | `/notes`       | JSON: the notes so far                                   |
| POST   | `/notes`       | Adds a note; needs an API token                          |
| any    | anything else  | JSON: a 404 error                                        |

Start the server (on port 3000, or `$PORT`; on `127.0.0.1`, or `$HOST`):

```bash
pnpm --filter @e-cline/http_server_example exec vp run start
```

Then, for example:

```bash
curl -X POST -H 'content-type: application/json' -d '{"greeting":"hi"}' localhost:3000/echo
```

```bash
curl -X PUT -d 'some body' 'localhost:3000/inspect?a=1'
```

`/events` streams its response: each line is sent when its event happens. `-N` stops curl buffering
the output, so the lines show up one at a time:

```bash
curl -N 'localhost:3000/events?count=10&intervalMs=250'
```

`/notes` uses a store shared between requests, which a middleware attaches to each one. Adding to it
goes through a second middleware, which checks an API token and attaches whose it was. Without a
token the answer is a 401, and without the `Content-Type` a 415: a JSON body has to say that's what
it is.

```bash
curl -X POST -H 'Authorization: Bearer secret-token' -H 'Content-Type: application/json' -d '{"text":"remember the milk"}' localhost:3000/notes
```

```bash
curl localhost:3000/notes
```

The application is a standard fetch handler, so it can be started from JavaScript too:

```bash
pnpm --filter @e-cline/http_server_example exec vp run start:js
```

Run the tests:

```bash
pnpm --filter @e-cline/http_server_example exec vp run test
```

## Notes

- `@rescript/webapi` is pinned to `0.1.0-experimental-0781ac8` (the npm `experimental` tag): the
  newest build that supports ReScript 12, which this workspace uses. The docs site describes the
  `alpha` builds, whose `peerDependencies` require ReScript 13. The `latest` tag is no use either:
  it still points at the package's first publish from 2024, which has no `URL` bindings.
- So, unlike in the docs, there is no `WebAPI.` namespace here: its modules are global (`Request`,
  `Response`, `Headers`, `URL`, `URLSearchParams`, and so on).
