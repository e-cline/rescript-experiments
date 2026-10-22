let run = HookImpl.renderOnServer
let isRunning = () => HookImpl.onServer.contents
let suspendedOn = (error: exn) =>
  switch error {
  | SuspenseImpl.Suspended(promise) => Some(promise)
  | _ => None
  }
