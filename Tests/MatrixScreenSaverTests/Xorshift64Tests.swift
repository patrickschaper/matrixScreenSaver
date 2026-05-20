func xorshift64Tests() {
    var rng1 = Xorshift64(seed: 42)
    var rng2 = Xorshift64(seed: 42)
    ok((0..<10).map { _ in rng1.next() } == (0..<10).map { _ in rng2.next() },
       "Xorshift64: identical seeds produce identical sequences")

    var rng3 = Xorshift64(seed: 42)
    var rng4 = Xorshift64(seed: 99999)
    ok((0..<10).map { _ in rng3.next() } != (0..<10).map { _ in rng4.next() },
       "Xorshift64: different seeds produce different sequences")
}
