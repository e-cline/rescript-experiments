/**
Groups any number of atom writes so effects they trigger are notified once, after every write in
the function has landed, rather than once per write. Returns the function's result.

Writes still take effect immediately inside the batch (a signal read there sees the new value);
only telling effects they're due is deferred -- and what happens then is up to each effect's
scheduler (see `EffectBase`). Nesting is fine: only the outermost `run` actually notifies. If the
function throws, the batch still ends (and effects are still notified) before the exception
propagates.
*/
let run: (unit => 'a) => 'a
