/*** The little of the Fetch API the server entry uses. */

type request
type response
type headers

@get external url: request => string = "url"
@get external headers: request => headers = "headers"
@send external header: (headers, string) => Nullable.t<string> = "get"

type url
@new external makeUrl: string => url = "URL"
@get external pathname: url => string = "pathname"

type init = {headers: dict<string>}
@new external makeResponse: (string, init) => response = "Response"
@scope("Response") @val external json: 'a => response = "json"
