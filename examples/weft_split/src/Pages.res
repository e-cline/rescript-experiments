@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The server components: one page per route, each rendering a different set of entrypoints.
*/

module Nav = {
  @weft.component({kind: Server})
  let make = () =>
    <nav>
      <Link id="home-link" href="/"> {Weft.Jsx.string("Home")} </Link>
      {Weft.Jsx.string(" ")}
      <Link id="other-link" href="/other"> {Weft.Jsx.string("Other")} </Link>
    </nav>
}

/** `/`: every entrypoint but `Chart`. */
module Home = {
  @weft.component({kind: Server})
  let make = async () => {
    let motto = await Secrets.motto()
    <main>
      <Nav />
      <h1> {Weft.Jsx.string("Home")} </h1>
      <p className="motto"> {Weft.Jsx.string(motto)} </p>
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
      <h1> {Weft.Jsx.string("Other")} </h1>
      <Chart rows=3 />
      <Counter label="other clicks" />
    </main>
}
