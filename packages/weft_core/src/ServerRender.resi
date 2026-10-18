/***
For server renderers: calling components outside the reconciler.

A server renderer calls component functions itself, with no fibers, so the hooks that keep state or
run effects have nowhere to keep it. `run` marks the call as a server render, so those hooks fail
with an error saying so (rather than "called outside a component"), while `Hooks.use` still works:
a promise that hasn't settled throws its `Suspended` exception, for the renderer to wait on and call
the component again.
*/

/**
Calls `f` as a server render. Only the synchronous part of `f` counts: the mark is removed when it
returns or throws, so a client render that runs afterwards (in the same process, as in a test) isn't
affected. A render that `run` is called from the middle of is set aside for the duration and
restored afterwards.
*/
let run: (unit => 'a) => 'a

/** Whether a server render (`run`) is in progress. */
let isRunning: unit => bool
