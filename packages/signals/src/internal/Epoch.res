let current = ref(0)

let advance = (): int => {
  current := current.contents + 1
  current.contents
}
