/** A value that doesn't fit: where (innermost first), and what was wrong. */
exception Mismatch(list<string>, string)

type t<'a> = {
  write: 'a => JSON.t,
  /** Reads a value, or throws `Mismatch`. `path` is where it is, innermost first. */
  read: (JSON.t, list<string>) => 'a,
  /** What a field that's left out reads as, if it can be (`None`, for an option). */
  missing: option<'a>,
}

let encode = (codec, value) => codec.write(value)

let where = path =>
  switch path {
  | list{} => "the request"
  | path => path->List.reverse->List.toArray->Array.join("")
  }

let decode = (codec, json) =>
  switch codec.read(json, list{}) {
  | value => Ok(value)
  | exception Mismatch(path, message) => Error(`${where(path)}: ${message}`)
  }

let describe = (json: JSON.t) =>
  switch json {
  | Null => "null"
  | Boolean(_) => "a boolean"
  | Number(_) => "a number"
  | String(_) => "a string"
  | Array(_) => "an array"
  | Object(_) => "an object"
  }

let mismatch = (path, expected, json) =>
  throw(Mismatch(path, `expected ${expected}, got ${describe(json)}`))

let string = {
  write: JSON.Encode.string,
  read: (json, path) =>
    switch json {
    | String(text) => text
    | _ => mismatch(path, "a string", json)
    },
  missing: None,
}

let maxInt = 2147483647.
let minInt = -2147483648.

let int = {
  write: JSON.Encode.int,
  read: (json, path) =>
    switch json {
    | Number(value) if Math.floor(value) == value && value >= minInt && value <= maxInt =>
      Float.toInt(value)
    | Number(_) => throw(Mismatch(path, "expected a whole number that fits in an int"))
    | _ => mismatch(path, "a whole number", json)
    },
  missing: None,
}

let float = {
  write: JSON.Encode.float,
  read: (json, path) =>
    switch json {
    // `JSON.parse` never gives an infinite number or `NaN`, but a `custom` codec's caller might.
    | Number(value) if Float.isFinite(value) => value
    | Number(_) => throw(Mismatch(path, "expected a finite number"))
    | _ => mismatch(path, "a number", json)
    },
  missing: None,
}

let bool = {
  write: JSON.Encode.bool,
  read: (json, path) =>
    switch json {
    | Boolean(value) => value
    | _ => mismatch(path, "a boolean", json)
    },
  missing: None,
}

let option = codec => {
  write: value =>
    switch value {
    | Some(value) => codec.write(value)
    | None => JSON.Encode.null
    },
  read: (json, path) =>
    switch json {
    | Null => None
    | json => Some(codec.read(json, path))
    },
  missing: Some(None),
}

let array = codec => {
  write: items => JSON.Encode.array(items->Array.map(codec.write)),
  read: (json, path) =>
    switch json {
    | Array(items) =>
      items->Array.mapWithIndex((item, index) =>
        codec.read(item, list{`[${Int.toString(index)}]`, ...path})
      )
    | _ => mismatch(path, "an array", json)
    },
  missing: None,
}

/** Whether `name` is one of `object`'s own properties (not one it inherits, like `constructor`). */
let hasOwn: (dict<JSON.t>, string) => bool = %raw(`(object, name) => Object.hasOwn(object, name)`)

/**
Sets `name` as an own property, whatever it is: assigning `__proto__` would change the object's
prototype instead.
*/
let defineField: (dict<'a>, string, 'a) => unit = %raw(`(object, name, value) => {
  Object.defineProperty(object, name, {value, writable: true, enumerable: true, configurable: true})
}`)

@scope("Object") @val external ownKeys: dict<JSON.t> => array<string> = "keys"

let fieldName = name => `.${name}`

let dict = codec => {
  write: values => {
    let fields = Dict.make()
    values
    ->Dict.toArray
    ->Array.forEach(((name, value)) => fields->defineField(name, codec.write(value)))
    JSON.Encode.object(fields)
  },
  read: (json, path) =>
    switch json {
    | Object(fields) =>
      let values = Dict.make()
      fields
      ->ownKeys
      ->Array.forEach(name =>
        values->defineField(
          name,
          codec.read(fields->Dict.getUnsafe(name), list{fieldName(name), ...path}),
        )
      )
      values
    | _ => mismatch(path, "an object", json)
    },
  missing: None,
}

let date = {
  write: date => JSON.Encode.string(date->Date.toISOString),
  read: (json, path) =>
    switch json {
    | String(text) =>
      let date = Date.fromString(text)

      // Only what `toISOString` writes: anything else `Date` would read differs between engines.
      if Float.isNaN(date->Date.getTime) || date->Date.toISOString != text {
        throw(Mismatch(path, "expected a date (an ISO 8601 string, as toISOString writes)"))
      }
      date
    | _ => mismatch(path, "a date (an ISO 8601 string)", json)
    },
  missing: None,
}

let map = (codec, ~decode, ~encode) => {
  write: value => codec.write(encode(value)),
  read: (json, path) =>
    switch decode(codec.read(json, path)) {
    | Ok(value) => value
    | Error(message) => throw(Mismatch(path, message))
    },
  missing: None,
}

let custom = (~encode, ~decode) => {
  write: encode,
  read: (json, path) =>
    switch decode(json) {
    | Ok(value) => value
    | Error(message) => throw(Mismatch(path, message))
    },
  missing: None,
}

type field<'a> = (string, t<'a>)

/** Reads the field `name` of `fields`, an own property, or what a missing one reads as. */
let readField = (fields, path, (name, codec): field<'a>) =>
  if fields->hasOwn(name) {
    codec.read(fields->Dict.getUnsafe(name), list{fieldName(name), ...path})
  } else {
    switch codec.missing {
    | Some(value) => value
    | None => throw(Mismatch(list{fieldName(name), ...path}, "missing"))
    }
  }

let writeField = (fields, (name, codec): field<'a>, value) =>
  fields->defineField(name, codec.write(value))

/** An object codec: `read` gets the object's fields once they're known to be one. */
let object_ = (~write, ~read) => {
  write: value => {
    let fields = Dict.make()
    write(fields, value)
    JSON.Encode.object(fields)
  },
  read: (json, path) =>
    switch json {
    | Object(fields) => read(fields, path)
    | _ => mismatch(path, "an object", json)
    },
  missing: None,
}

let object1 = (a, make, unmake) =>
  object_(
    ~write=(fields, value) => writeField(fields, a, unmake(value)),
    ~read=(fields, path) => make(readField(fields, path, a)),
  )

let object2 = (a, b, make, unmake) =>
  object_(
    ~write=(fields, value) => {
      let (va, vb) = unmake(value)
      writeField(fields, a, va)
      writeField(fields, b, vb)
    },
    ~read=(fields, path) => {
      let va = readField(fields, path, a)
      let vb = readField(fields, path, b)
      make(va, vb)
    },
  )

let object3 = (a, b, c, make, unmake) =>
  object_(
    ~write=(fields, value) => {
      let (va, vb, vc) = unmake(value)
      writeField(fields, a, va)
      writeField(fields, b, vb)
      writeField(fields, c, vc)
    },
    ~read=(fields, path) => {
      let va = readField(fields, path, a)
      let vb = readField(fields, path, b)
      let vc = readField(fields, path, c)
      make(va, vb, vc)
    },
  )

let object4 = (a, b, c, d, make, unmake) =>
  object_(
    ~write=(fields, value) => {
      let (va, vb, vc, vd) = unmake(value)
      writeField(fields, a, va)
      writeField(fields, b, vb)
      writeField(fields, c, vc)
      writeField(fields, d, vd)
    },
    ~read=(fields, path) => {
      let va = readField(fields, path, a)
      let vb = readField(fields, path, b)
      let vc = readField(fields, path, c)
      let vd = readField(fields, path, d)
      make(va, vb, vc, vd)
    },
  )

let object5 = (a, b, c, d, e, make, unmake) =>
  object_(
    ~write=(fields, value) => {
      let (va, vb, vc, vd, ve) = unmake(value)
      writeField(fields, a, va)
      writeField(fields, b, vb)
      writeField(fields, c, vc)
      writeField(fields, d, vd)
      writeField(fields, e, ve)
    },
    ~read=(fields, path) => {
      let va = readField(fields, path, a)
      let vb = readField(fields, path, b)
      let vc = readField(fields, path, c)
      let vd = readField(fields, path, d)
      let ve = readField(fields, path, e)
      make(va, vb, vc, vd, ve)
    },
  )

let object6 = (a, b, c, d, e, f, make, unmake) =>
  object_(
    ~write=(fields, value) => {
      let (va, vb, vc, vd, ve, vf) = unmake(value)
      writeField(fields, a, va)
      writeField(fields, b, vb)
      writeField(fields, c, vc)
      writeField(fields, d, vd)
      writeField(fields, e, ve)
      writeField(fields, f, vf)
    },
    ~read=(fields, path) => {
      let va = readField(fields, path, a)
      let vb = readField(fields, path, b)
      let vc = readField(fields, path, c)
      let vd = readField(fields, path, d)
      let ve = readField(fields, path, e)
      let vf = readField(fields, path, f)
      make(va, vb, vc, vd, ve, vf)
    },
  )

let object7 = (a, b, c, d, e, f, g, make, unmake) =>
  object_(
    ~write=(fields, value) => {
      let (va, vb, vc, vd, ve, vf, vg) = unmake(value)
      writeField(fields, a, va)
      writeField(fields, b, vb)
      writeField(fields, c, vc)
      writeField(fields, d, vd)
      writeField(fields, e, ve)
      writeField(fields, f, vf)
      writeField(fields, g, vg)
    },
    ~read=(fields, path) => {
      let va = readField(fields, path, a)
      let vb = readField(fields, path, b)
      let vc = readField(fields, path, c)
      let vd = readField(fields, path, d)
      let ve = readField(fields, path, e)
      let vf = readField(fields, path, f)
      let vg = readField(fields, path, g)
      make(va, vb, vc, vd, ve, vf, vg)
    },
  )

let object8 = (a, b, c, d, e, f, g, h, make, unmake) =>
  object_(
    ~write=(fields, value) => {
      let (va, vb, vc, vd, ve, vf, vg, vh) = unmake(value)
      writeField(fields, a, va)
      writeField(fields, b, vb)
      writeField(fields, c, vc)
      writeField(fields, d, vd)
      writeField(fields, e, ve)
      writeField(fields, f, vf)
      writeField(fields, g, vg)
      writeField(fields, h, vh)
    },
    ~read=(fields, path) => {
      let va = readField(fields, path, a)
      let vb = readField(fields, path, b)
      let vc = readField(fields, path, c)
      let vd = readField(fields, path, d)
      let ve = readField(fields, path, e)
      let vf = readField(fields, path, f)
      let vg = readField(fields, path, g)
      let vh = readField(fields, path, h)
      make(va, vb, vc, vd, ve, vf, vg, vh)
    },
  )

type case<'a> = {
  name: string,
  /** Reads the variant from the object's fields (its payload, `value`, if it has one). */
  readCase: (dict<JSON.t>, list<string>) => 'a,
}

let case = (name, codec, make) => {
  name,
  readCase: (fields, path) => make(readField(fields, path, ("value", codec))),
}

let constant = (name, value) => {name, readCase: (_, _) => value}

type tagged = {tag: string, payload: option<JSON.t>}

let tagged = (tag, codec, payload) => {tag, payload: Some(codec.write(payload))}
let tag = tag => {tag, payload: None}

let variant = (cases, ~encode) => {
  write: value => {
    let {tag, payload} = encode(value)
    let fields = dict{"tag": JSON.Encode.string(tag)}
    payload->Option.forEach(payload => fields->Dict.set("value", payload))
    JSON.Encode.object(fields)
  },
  read: (json, path) =>
    switch json {
    | Object(fields) =>
      let tagPath = list{fieldName("tag"), ...path}
      let tag = readField(fields, path, ("tag", string))
      // Found by comparing names, never by looking a property up.
      switch cases->Array.find(case => case.name == tag) {
      | Some(case) => case.readCase(fields, path)
      | None =>
        throw(
          Mismatch(
            tagPath,
            `expected one of ${cases->Array.map(case => `"${case.name}"`)->Array.join(", ")}`,
          ),
        )
      }
    | _ => mismatch(path, "an object", json)
    },
  missing: None,
}
