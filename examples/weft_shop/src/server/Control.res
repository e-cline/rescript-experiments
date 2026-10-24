@@weft.server

/***
The tests' starting point (the harness's, through `tests/ShopControl.res`, and the browser tests',
through `/test/reset`): every latency gate closed, the catalog's stock, the layouts and the users as
they started, no sessions (and every new one in the experiment's first half), and no blocks or order pages that refresh themselves.
*/

let reset = () => {
  Latency.reset()
  Db.seed()
  Cms.liveEvery := 0
  Cms.seed()
  Session.reset()
  Session.fixedBucket := Some("a")
  Pages.pollEvery := None
}
