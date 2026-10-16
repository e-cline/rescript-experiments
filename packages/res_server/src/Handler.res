/** A request handler: everything in this framework that answers a request is one of these. */
type t = RequestContext.t => promise<Response.t>
