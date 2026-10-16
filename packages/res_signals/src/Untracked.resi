/**
Runs the function with no active consumer, so any signal it reads is *not* registered as a
dependency of whatever computed/effect is currently running -- for the rare case where a
computation genuinely shouldn't react to a signal it needs to read. Returns the function's
result, and restores the previous consumer even if it throws.
*/
let run: (unit => 'a) => 'a
