module Renderer = Fiber.Reconciler.Make(DomHost)

DomHost.runEvent := (f => Renderer.flushSync(f))

type root = Renderer.root

let createRoot = (container: Dom.element) => {
  Dom.setTextContent(container, "")
  Renderer.createRoot(container)
}

let render = Renderer.render
let flushSync = Renderer.flushSync

let maxActRounds = 100

let act = f => {
  f()
  Renderer.flushAllWork()
  let rounds = ref(0)
  while Renderer.flushPassiveEffects() {
    rounds := rounds.contents + 1
    if rounds.contents > maxActRounds {
      JsError.throwWithMessage("FiberDom: effects keep scheduling updates")
    }
    Renderer.flushAllWork()
  }
}

let unmount = root => act(() => Renderer.unmount(root))
