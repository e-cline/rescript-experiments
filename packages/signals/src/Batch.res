let run = (f: unit => 'a): 'a => {
  Node.batchDepth := Node.batchDepth.contents + 1
  let finish = () => {
    Node.batchDepth := Node.batchDepth.contents - 1
    Node.settle()
  }
  switch f() {
  | result =>
    finish()
    result
  | exception e =>
    finish()
    throw(e)
  }
}
