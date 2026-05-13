import Foundation

/// A fast, seedable pseudo-random number generator (xorshift64).
/// Produces identical sequences from the same seed, enabling deterministic
/// sync across all screen saver instances on the same machine.
struct Xorshift64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 6364136223846793005 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
