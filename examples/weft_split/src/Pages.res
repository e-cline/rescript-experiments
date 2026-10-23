/***
The server components: one page per route, each rendering a different set of entrypoints.
*/

module Nav = {
  @weft.component({kind: Server})
  let make = () =>
    <nav>
      <Link id="home-link" href="/"> {WeftDom.Jsx.string("Home")} </Link>
      {WeftDom.Jsx.string(" ")}
      <Link id="other-link" href="/other"> {WeftDom.Jsx.string("Other")} </Link>
    </nav>
}

/** `/`: every entrypoint but `Chart`. */
module Home = {
  @weft.component({kind: Server})
  let make = async () => {
    let motto = await Secrets.motto()
    <main>
      <Nav />
      <h1> {WeftDom.Jsx.string("Home")} </h1>
      <p className="motto"> {WeftDom.Jsx.string(motto)} </p>
      <Counter label="clicks" />
      <Widgets.Toggle label="Details" />
      <Widgets.Error message="Nothing went wrong" />
      <Fancy text="fancy" />
      <Plain text="  plain  " />
      <Outer title="Outer" />
    </main>
  }
}

/** `/other`: the chart, and a counter. */
module Other = {
  @weft.component({kind: Server})
  let make = () =>
    <main>
      <Nav />
      <h1> {WeftDom.Jsx.string("Other")} </h1>
      <Chart rows=3 />
      <Counter label="other clicks" />
    </main>
}
