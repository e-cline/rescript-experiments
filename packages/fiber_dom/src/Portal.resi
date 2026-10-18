/***
Renders children into another DOM element, such as a dialog layer at the end of `<body>`, while they
stay in the component's place in the tree: context, error boundaries and effects work as if they
were there.

```rescript
<FiberDom.Portal container=dialogLayer> <Dialog /> </FiberDom.Portal>
```

DOM events in the portal bubble through the DOM, to `container`'s ancestors, not to the elements
around the portal in the component tree (unlike React, which re-dispatches them through the tree).
*/

type props = {container: Dom.element, children: Fiber.Element.t}

/** The component form: `<Portal container> ... </Portal>`. */
let make: Fiber.JsxCore.component<props>

/** `children`, rendered into `container`. */
let create: (Fiber.Element.t, ~container: Dom.element, ~key: string=?) => Fiber.Element.t
