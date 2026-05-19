import Foundation

// Test runner — compiled as part of a multi-file swiftc invocation.
// This file is the sole top-level entry point (named main.swift by convention).

var allPassed = true

func check(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
    if condition {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name) [\(file):\(line)]")
        allPassed = false
    }
}

func runTests() {
    // T1: Xorshift64 with identical seeds produces identical sequences
    var rng1 = Xorshift64(seed: 42)
    var rng2 = Xorshift64(seed: 42)
    let seq1 = (0..<10).map { _ in rng1.next() }
    let seq2 = (0..<10).map { _ in rng2.next() }
    check(seq1 == seq2, "T1: identical seeds produce identical sequences")

    // T2: Xorshift64 with different seeds produces different sequences
    var rng3 = Xorshift64(seed: 42)
    var rng4 = Xorshift64(seed: 99999)
    let seq3 = (0..<10).map { _ in rng3.next() }
    let seq4 = (0..<10).map { _ in rng4.next() }
    check(seq3 != seq4, "T2: different seeds produce different sequences")

    // T3: NativeMatrixRenderer has a seedOffset property that defaults to 0
    let renderer = NativeMatrixRenderer()
    check(renderer.seedOffset == 0, "T3: seedOffset defaults to 0")

    // T4: Two renderers with different seedOffsets diverge after equal frames
    var r1 = NativeMatrixRenderer()
    var r2 = NativeMatrixRenderer()
    r1.seedOffset = 0
    r2.seedOffset = UInt64(0xDEAD_BEEF)
    var cfg = NativeMatrixRenderer.Configuration()
    cfg.neoMessageSceneEnabled = false
    cfg.numberSceneEnabled = false
    r1.resize(to: TerminalSize(columns: 40, rows: 20))
    r2.resize(to: TerminalSize(columns: 40, rows: 20))
    r1.updateConfiguration(cfg)
    r2.updateConfiguration(cfg)
    r1.start()
    r2.start()
    for _ in 0..<60 { r1.advance(); r2.advance() }
    var differ = false
    outer: for row in 0..<20 {
        for col in 0..<40 {
            if r1[row, col] != r2[row, col] { differ = true; break outer }
        }
    }
    check(differ, "T4: renderers with different seedOffsets diverge after 60 frames")
}

runTests()
print(allPassed ? "\nAll tests passed." : "\nSome tests FAILED.")
exit(allPassed ? 0 : 1)
