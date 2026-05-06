struct TerminalSize: Equatable {
    let columns: Int
    let rows: Int
}

struct TerminalColor: Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    /// Creates a color from explicit RGB channel values.
    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Creates a color from a packed 24-bit RGB hex value.
    init(hex: UInt32) {
        red = UInt8((hex >> 16) & 0xff)
        green = UInt8((hex >> 8) & 0xff)
        blue = UInt8(hex & 0xff)
    }
}
