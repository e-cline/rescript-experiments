/***
Prices, in the currency the shopper picked. Formatted by hand, not with `Intl`, so the server and the
browser write exactly the same text (hydration compares them).
*/

open Types

let currencies = [USD, EUR, GBP]

let code = currency =>
  switch currency {
  | USD => "USD"
  | EUR => "EUR"
  | GBP => "GBP"
  }

let fromCode = code =>
  switch code {
  | "EUR" => Some(EUR)
  | "GBP" => Some(GBP)
  | "USD" => Some(USD)
  | _ => None
  }

let symbol = currency =>
  switch currency {
  | USD => "$"
  | EUR => "€"
  | GBP => "£"
  }

/** Cents of the store's currency (dollars) in `currency`'s cents. */
let convert = (cents: cents, currency) =>
  switch currency {
  | USD => cents
  | EUR => Float.toInt(Math.round(Int.toFloat(cents) *. 0.92))
  | GBP => Float.toInt(Math.round(Int.toFloat(cents) *. 0.79))
  }

/** `cents` (in dollars' cents) as `currency` writes it: `$1,234.50`. */
let format = (cents: cents, currency) => {
  let converted = convert(cents, currency)
  let negative = converted < 0
  let converted = negative ? -converted : converted
  let whole = Int.toString(converted / 100)
  let fraction = Int.toString(mod(converted, 100))->String.padStart(2, "0")
  // Thousands separators, from the right.
  let length = String.length(whole)
  let grouped = Array.fromInitializer(~length, index => {
    let digit = whole->String.charAt(index)
    let fromRight = length - index
    index > 0 && mod(fromRight, 3) == 0 ? "," ++ digit : digit
  })->Array.join("")
  `${negative ? "-" : ""}${symbol(currency)}${grouped}.${fraction}`
}
