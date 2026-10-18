@@directive("'use weft entrypoint'")

/***
A part of the page that can be fetched again by itself: a built-in entrypoint a server component
wraps around a subtree.

```rescript
// in a server component
<WeftServer.Frame name="comments" src={`/notes/${id}/comments`}>
  <Comments noteId=id />
</WeftServer.Frame>
```

It shows its `children` (rendered on the server with the rest of the page) until it's refetched
(`Navigation.useFrame(name).refetch()`), then fetches `src` (or the URL `refetch` is given) as a
payload, and renders that in their place, in a transition. The route at `src` renders just that
subtree. If a later `navigate` or `refresh` gives the frame new `children`, those show instead:
whichever is newer wins. Refetches of one frame replace each other, as navigations do.

It's marked as an entrypoint by hand (this package doesn't use `ppx_weft`), with the directive that
puts it in the Vite plugin's reference map.
*/

type props = {name: string, src: string, children: WeftCore.Element.t}

let make: WeftCore.JsxCore.component<props>
