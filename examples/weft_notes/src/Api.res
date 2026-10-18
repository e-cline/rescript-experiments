/*** The client's requests to the app's own routes (posting a comment, say). */

type response = {ok: bool, status: int}
@val external fetch: (string, {..}) => promise<response> = "fetch"

/** Posts `body` (JSON) to `url`, failing on anything but a 2xx. */
let post = async (url, body: JSON.t) => {
  let response = await fetch(
    url,
    {
      "method": "POST",
      "headers": {"content-type": "application/json"},
      "body": JSON.stringify(body),
    },
  )
  if !response.ok {
    JsError.throwWithMessage(
      `posting to ${url} failed with status ${Int.toString(response.status)}`,
    )
  }
}
