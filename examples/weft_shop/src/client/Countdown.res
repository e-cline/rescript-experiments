/***
The time left on an offer, ticking. The first render uses the server's clock (`now`, a prop), so the
HTML and the render hydrating it say the same; from then on, the browser's.
*/

module Jsx = WeftDom.Jsx

let format = ms => {
  let seconds = Math.Int.max(0, Float.toInt(ms /. 1000.0))
  let pad = n => Int.toString(n)->String.padStart(2, "0")
  `${Int.toString(seconds / 3600)}h ${pad(mod(seconds / 60, 60))}m ${pad(mod(seconds, 60))}s`
}

open WeftCss

module Styles = {
  let countdown = Css.class({fontVariantNumeric: TabularNums, color: Var(Theme.accent)})
}

@weft.component({kind: Entrypoint})
let make = (~id: string, ~endsAt: float, ~now as serverNow: float) => {
  let (now, setNow) = Weft.Hooks.useState(() => serverNow)
  Weft.Hooks.useEffect0(() => {
    setNow(_ => Date.now())
    let timer = setInterval(() => setNow(_ => Date.now()), 1000)
    Some(() => clearInterval(timer))
  })
  <span className={Styles.countdown} dataId=id>
    {Jsx.string(endsAt <= now ? "Ended" : `Ends in ${format(endsAt -. now)}`)}
  </span>
}
