/***
Short messages that come and go ("Added to your cart"), in a corner of the page, read out as they
arrive (a polite live region; a `#danger` one is an alert).

```rescript
// Once, in the page (or `<ToastViewport />`, the ready-made entrypoint, from a server component):
<Toast.Viewport />
// Anywhere in client code:
Toast.add(~title="Added to your cart", ~tone=#success, ())
```

Each closes itself after `duration` ms (`0`: when it's dismissed), or with its dismiss button. While
the pointer or the focus is in the viewport, nothing closes, so a toast being read, or about to be
clicked, stays. An `action` (a label and what it does) is a button in it.

Toasts go to a manager: the default one, which `add` and `Viewport` use unless given another
(`createManager()`, for a part of the page with toasts of its own, or a test).

The viewport is interactive (it keeps state), so it renders inside an entrypoint.
*/
open WeftCss

module Dom = WeftDom.Dom

type tone = [#neutral | #success | #danger]

type toast = {
  id: int,
  title: string,
  description: option<string>,
  tone: tone,
  /** How long it stays, in ms: `0` for until it's dismissed. */
  duration: int,
  action: option<(string, unit => unit)>,
}

type manager = {
  mutable toasts: array<toast>,
  mutable next: int,
  listeners: array<unit => unit>,
  subscribe: (unit => unit) => unit => unit,
}

let createManager = (): manager => {
  let listeners = []
  {
    toasts: [],
    next: 1,
    listeners,
    subscribe: listener => {
      listeners->Array.push(listener)
      () => {
        let index = listeners->Array.indexOf(listener)
        if index >= 0 {
          listeners->Array.splice(~start=index, ~remove=1, ~insert=[])
        }
      }
    },
  }
}

/** The manager `add` and `Viewport` use unless given another. */
let defaultManager = createManager()

let update = (manager, toasts) => {
  manager.toasts = toasts
  manager.listeners->Array.forEach(listener => listener())
}

/** Shows a toast, and gives its id (for `dismiss`). */
let add = (
  ~manager=defaultManager,
  ~title: string,
  ~description: option<string>=?,
  ~tone: tone=#neutral,
  ~duration=5000,
  ~action: option<(string, unit => unit)>=?,
  (),
) => {
  let id = manager.next
  manager.next = id + 1
  update(manager, [...manager.toasts, {id, title, description, tone, duration, action}])
  id
}

/** Takes a toast away. */
let dismiss = (~manager=defaultManager, id) =>
  update(manager, manager.toasts->Array.filter(toast => toast.id != id))

/** The toasts `manager` has now, in a component (rendering again when they change). */
let useToasts = manager =>
  Weft.Hooks.useSyncExternalStore(
    ~subscribe=manager.subscribe,
    ~getSnapshot=() => manager.toasts,
    ~getServerSnapshot=() => [],
  )

module Styles = {
  let layer = Tokens.layer
  let viewport = Css.class(
    ~layer,
    {
      position: Fixed,
      zIndex: 50,
      insetInlineEnd: Var(Tokens.spaceLg),
      display: Flex,
      flexDirection: Column,
      gap: Var(Tokens.spaceSm),
      inlineSize: Raw("min(360px, 100vw - 32px)"),
      margin: Zero,
      padding: Zero,
      listStyle: None,
      pointerEvents: None,
    },
  )
  let bottom = Css.class(~layer, {insetBlockEnd: Var(Tokens.spaceLg)})
  let top = Css.class(~layer, {insetBlockStart: Var(Tokens.spaceLg)})
  let enter = Css.keyframes(
    ~layer,
    [Css.frame(~at="from", {opacity: 0., transform: "translateY(8px)"})],
  )
  let toast = Css.class(
    ~layer,
    {
      display: Grid,
      gridTemplateColumns: "minmax(0, 1fr) auto",
      alignItems: Start,
      columnGap: Var(Tokens.spaceSm),
      padding: Pair(Var(Tokens.spaceMd), Var(Tokens.spaceMd)),
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.bg),
      backgroundColor: Var(Tokens.fg),
      borderRadius: Var(Tokens.radiusMd),
      boxShadow: Tokens.value(Tokens.shadowMd),
      pointerEvents: Auto,
      animationName: enter,
      animationDuration: Tokens.value(Tokens.durationMedium),
      animationTimingFunction: "ease-out",
    },
  )
  let success = Css.class(
    ~layer,
    {color: Var(Tokens.successFg), backgroundColor: Var(Tokens.success)},
  )
  let danger = Css.class(~layer, {color: Var(Tokens.dangerFg), backgroundColor: Var(Tokens.danger)})
  let text = Css.class(~layer, {display: Flex, flexDirection: Column, gap: Px(2), minWidth: Zero})
  let title = Css.class(~layer, {fontWeight: 600})
  let description = Css.class(~layer, {opacity: 0.85})
  let actions = Css.class(~layer, {display: Flex, alignItems: Center, gap: Var(Tokens.spaceXs)})
  /** The toast's buttons, in its colours. */
  let button = Css.class(
    ~layer,
    {
      color: Raw("inherit"),
      backgroundColor: Transparent,
      borderColor: CurrentColor,
      selectors: [
        ("&:hover:not(:disabled)", Css.style({backgroundColor: Rgba(255, 255, 255, 0.15)})),
      ],
    },
  )
  let dismiss = Css.class(
    ~layer,
    {
      color: Raw("inherit"),
      selectors: [
        ("&:hover:not(:disabled)", Css.style({backgroundColor: Rgba(255, 255, 255, 0.15)})),
      ],
    },
  )
}

module Item = {
  @weft.component
  let make = (~toast: toast, ~manager: manager, ~paused: bool) => {
    // What's left of its time, as of the last pause.
    let remaining = Weft.Hooks.useRef(Int.toFloat(toast.duration))
    Weft.Hooks.useEffect2(() =>
      if paused || toast.duration <= 0 {
        None
      } else {
        let started = Date.now()
        let timer = setTimeout(
          () => dismiss(~manager, toast.id),
          Float.toInt(Math.max(0., remaining.current)),
        )
        Some(
          () => {
            clearTimeout(timer)
            remaining.current = remaining.current -. (Date.now() -. started)
          },
        )
      }
    , (paused, toast.id))
    <li
      className={Css.cx([
        Styles.toast,
        switch toast.tone {
        | #neutral => ""
        | #success => Styles.success
        | #danger => Styles.danger
        },
      ])}
      role=?{toast.tone == #danger ? Some("alert") : None}
      dataVariant={(toast.tone :> string)}
    >
      <div className=Styles.text>
        <span className=Styles.title> {WeftDom.Jsx.string(toast.title)} </span>
        {switch toast.description {
        | Some(description) =>
          <span className=Styles.description> {WeftDom.Jsx.string(description)} </span>
        | None => WeftDom.Jsx.null
        }}
      </div>
      <div className=Styles.actions>
        {switch toast.action {
        | Some((label, run)) =>
          <Button
            size=#sm
            variant=#outline
            className=Styles.button
            onClick={_ => {
              run()
              dismiss(~manager, toast.id)
            }}
          >
            {WeftDom.Jsx.string(label)}
          </Button>
        | None => WeftDom.Jsx.null
        }}
        <IconButton
          label="Dismiss"
          size=#sm
          className=Styles.dismiss
          onClick={_ => dismiss(~manager, toast.id)}
        >
          {WeftDom.Jsx.string("×")}
        </IconButton>
      </div>
    </li>
  }
}

module Viewport = {
  /** Where the toasts show: the page's bottom (or top) inline end. Render it once. */
  @weft.component
  let make = (
    ~manager=defaultManager,
    ~placement: [#bottom | #top]=#bottom,
    ~label="Notifications",
    ~className=?,
    ~dataId=?,
  ) => {
    let toasts = useToasts(manager)
    let (hovered, setHovered) = Weft.Hooks.useState(() => false)
    let (focused, setFocused) = Weft.Hooks.useState(() => false)
    let paused = hovered || focused
    <section ariaLabel=label ?dataId>
      <ol
        className={Host.classes(
          [Styles.viewport, placement == #top ? Styles.top : Styles.bottom],
          className,
        )}
        ariaLive="polite"
        ariaRelevant="additions"
        onPointerEnter={_ => setHovered(_ => true)}
        onPointerLeave={_ => setHovered(_ => false)}
        onFocusIn={_ => setFocused(_ => true)}
        onFocusOut={event =>
          switch Dom.Event.relatedTarget(event)->Nullable.toOption {
          | Some(next) if Dom.contains(Dom.Event.currentTarget(event), next) => ()
          | _ => setFocused(_ => false)
          }}
      >
        {toasts
        ->Array.map(toast => <Item key={Int.toString(toast.id)} toast manager paused />)
        ->WeftDom.Jsx.array}
      </ol>
    </section>
  }
}
