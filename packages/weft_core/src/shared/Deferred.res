type t<'value> = {
  promise: promise<'value>,
  resolve: 'value => unit,
  reject: JsError.t => unit,
}

let make = () => {
  let fulfil = ref(_ => ())
  let fail = ref(_ => ())
  let promise = Promise.make((resolve, reject) => {
    fulfil := resolve
    fail := reject
  })
  // Marked pending already, so `SuspenseImpl.track` (from `Hooks.use` or `Lazy.fromPromise`) leaves
  // it alone: the status is set here, at once, not in a `then` callback.
  SuspenseImpl.setStatus(promise, SuspenseImpl.pending)
  // Handled, so a rejection nothing has read yet isn't reported as unhandled.
  promise->Promise.catch(_ => Promise.resolve(Unsafe.fromUnknown(Unsafe.nothing)))->ignore
  let isPending = () =>
    SuspenseImpl.status(promise)->Nullable.toOption == Some(SuspenseImpl.pending)
  {
    promise,
    resolve: value =>
      if isPending() {
        SuspenseImpl.setStatus(promise, SuspenseImpl.fulfilled)
        SuspenseImpl.setValue(promise, value)
        fulfil.contents(value)
      },
    reject: error =>
      if isPending() {
        SuspenseImpl.setStatus(promise, SuspenseImpl.rejected)
        SuspenseImpl.setReason(promise, Unsafe.toUnknown(error))
        fail.contents(error)
      },
  }
}

let isSettled = deferred =>
  SuspenseImpl.status(deferred.promise)->Nullable.toOption != Some(SuspenseImpl.pending)
