open Vitest

describe("Debug.assert_", () => {
  test("does not throw when the condition holds", t => {
    t->expect(() => Debug.assert_(true))->Expect.not->Expect.toThrow
  })

  test("throws AssertionError with the default message when the condition fails", t => {
    t->expect(() => Debug.assert_(false))->Expect.toThrow(~message="Assertion failed")
  })

  test("throws with a custom message built by the thunk", t => {
    t
    ->expect(() => Debug.assert_(false, ~message=() => "custom failure"))
    ->Expect.toThrow(~message="custom failure")
  })

  test("never calls the message thunk when the condition holds", t => {
    let calls = ref(0)
    Debug.assert_(
      true,
      ~message=() => {
        calls := calls.contents + 1
        "should not be built"
      },
    )
    t->expect(calls.contents)->Expect.toBe(0)
  })
})

describe("Debug.fail", () => {
  test("always throws AssertionError with the default message", t => {
    t->expect(() => Debug.fail())->Expect.toThrow(~message="Assertion failed")
  })

  test("always throws with a custom message", t => {
    t
    ->expect(() => Debug.fail(~message=() => "unreachable"))
    ->Expect.toThrow(~message="unreachable")
  })
})

describe("Debug.debugAssert", () => {
  // `@e-cline/js_env`'s default export-condition resolution in this test
  // environment is "development" -- see `Env.res`'s header comment. This
  // test deliberately depends on that: it documents which variant test runs
  // actually exercise, since `Env_test.res` deliberately doesn't (it only
  // checks that `isDev`/`isProd` come through as opposite booleans, not which
  // concrete values they resolve to here).
  test("isDev is true in this test environment", t => {
    t->expect(Debug.isDev)->Expect.toBe(true)
  })

  test("does not throw when the condition holds", t => {
    t->expect(() => Debug.debugAssert(true))->Expect.not->Expect.toThrow
  })

  test("throws when the condition fails, since isDev is true here", t => {
    t
    ->expect(() => Debug.debugAssert(false, ~message=() => "debug failure"))
    ->Expect.toThrow(~message="debug failure")
  })

  test("never calls the message thunk when the condition holds", t => {
    let calls = ref(0)
    Debug.debugAssert(
      true,
      ~message=() => {
        calls := calls.contents + 1
        "should not be built"
      },
    )
    t->expect(calls.contents)->Expect.toBe(0)
  })
})
