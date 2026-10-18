@@directive("'use weft entrypoint'")

/***
A part of the page that can be fetched again by itself: a built-in entrypoint a server component
wraps around a subtree.

```rescript
// in a server component
<WeftServer.Frame src={`/notes/${id}/comments`}>
  <Comments noteId=id />
</WeftServer.Frame>

// in an entrypoint inside it
let comments = WeftServer.Navigation.useFrame()
<button onClick={_ => comments.refetch()->ignore}> {...} </button>
```

It's `Navigation.useRefetchable` as an entrypoint a server component can place: it shows its
`children` (rendered on the server with the rest of the page) until it's refetched, then fetches
`src` (or the URL `refetch` is given) as a payload, and renders that in their place, in a
transition. The route at `src` renders just that subtree. Newer `children` (from a `navigate` or
`refresh`) win over what was refetched, and refetches replace each other, as navigations do.

Entrypoints inside it reach it with `Navigation.useFrame`, the nearest frame above them. Something
elsewhere on the page that needs to refetch it is better made an entrypoint of its own around the
part it refetches, with `useRefetchable`.

It's marked as an entrypoint by hand (this package doesn't use `ppx_weft`), with the directive that
puts it in the Vite plugin's reference map.
*/

type props = {src: string, children: WeftCore.Element.t}

let make: WeftCore.JsxCore.component<props>
