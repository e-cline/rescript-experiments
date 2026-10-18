let run = (f: unit => 'a): 'a => {
  let previous = Node.activeConsumer.contents
  Node.activeConsumer := None
  switch f() {
  | result =>
    Node.activeConsumer := previous
    result
  | exception e =>
    Node.activeConsumer := previous
    throw(e)
  }
}
