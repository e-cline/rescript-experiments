/***
A router turns routes into a handler: it gives each request to the first
route that matches it.

```rescript
let handler = Router.make([
  Route.get(list{}, home),
  Route.get(list{"users", ":id"}, showUser),
  Route.scope(list{"admin"}, [requireAdmin], [
    Route.get(list{"users"}, listUsers),
  ]),
])
```

A request to a path no route has gets a plain 404. One to a path that a route
has, but with a method none of them takes, gets a 405 Method Not Allowed
listing the methods that would work in `Allow` (or, for `OPTIONS`, a 204
listing them). To answer either some other way, end with a route that matches
everything: `Route.any(list{"**"}, notFound)`.

A router is a handler like any other, so it can be wrapped in middleware, or
be the handler of a route in another router. Give that route a `"**"` and the
inner router matches against what's left of the path:

```rescript
Route.any(list{"api", "v1", "**"}, Router.make(apiRoutes))
```

Two things follow from the inner router being an ordinary handler:

- Its answer is final. If none of its routes match, its 404 is the response;
  the outer router doesn't go on to its own later routes. For routes that
  share a prefix but should be tried along with the rest, use `Route.scope`,
  which adds them to the outer router's own list.
- It sees the parameters the outer route bound, and a parameter of its own
  with the same name takes that name over for its handlers.
*/

let make = (routes: array<Route.t>): Handler.t => {
  // One route standing for all of them, tried in order.
  let route = Route.scope(list{}, [], routes)
  async ctx =>
    switch route->Route.handle(ctx) {
    | Some(response) => await response
    | None =>
      switch route->Route.mismatch(ctx) {
      | Some(response) => await response
      | None => Respond.notFound()
      }
    }
}
