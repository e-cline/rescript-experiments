let digits = "0123456789abcdefghijklmnopqrstuvwxyz"

// 36⁶: six base-36 digits.
let range = 2176782336.

type encoder
@new external encoder: unit => encoder = "TextEncoder"
@send external encode: (encoder, string) => array<int> = "encode"

// Over the UTF-8 bytes, as the PPX (in OCaml, whose strings are bytes) hashes them.
let fnv1a = text => {
  let hash = ref(0x811c9dc5)
  encoder()
  ->encode(text)
  ->Array.forEach(byte => hash := Math.Int.imul(hash.contents ^^^ byte, 0x01000193))
  // Unsigned (bsc drops a `>>> 0`, which in its int model changes nothing).
  let hash = Int.toFloat(hash.contents)
  hash < 0. ? hash +. 4294967296. : hash
}

let ofFileId = fileId => {
  let n = ref(Math.floor(fnv1a(fileId) % range))
  let out = Array.make(~length=6, "0")
  for i in 5 downto 0 {
    out->Array.setUnsafe(i, digits->String.charAt(Float.toInt(n.contents % 36.)))
    n := Math.floor(n.contents /. 36.)
  }
  "w" ++ out->Array.join("")
}

let suffix = /_(w[0-9a-z]{6})$/

let ofName = name =>
  switch suffix->RegExp.exec(name) {
  | Some(result) => result->RegExp.Result.matches->Array.get(0)->Option.flatMap(id => id)
  | None => None
  }

let unique = ids => {
  let seen = Set.make()
  ids->Array.filter(id =>
    if seen->Set.has(id) {
      false
    } else {
      seen->Set.add(id)
      true
    }
  )
}

let ofClassList = classes =>
  classes
  ->String.split(" ")
  ->Array.filterMap(name => ofName(String.trim(name)))
  ->unique

// A name's end: what can't continue a CSS identifier follows it.
let inTextPattern = /_(w[0-9a-z]{6})(?![0-9A-Za-z_-])/g

let inText = text =>
  text
  ->String.match(inTextPattern)
  ->Option.getOr([])
  ->Array.filterMap(found => found->Option.map(found => found->String.slice(~start=1)))
  ->unique
