func nativeMatrixRendererTests() {
    ok(NativeMatrixRenderer().seedOffset == 0,
       "NativeMatrixRenderer: seedOffset defaults to 0")

    let palette = NativeMatrixRenderer().levelColors
    let hasNoPureWhite = !palette.contains { color in
        color.red == 255 && color.green == 255 && color.blue == 255
    }
    ok(hasNoPureWhite,
       "NativeMatrixRenderer: palette avoids pure white highlight")

    let hasMaxGreenHighlight = palette.contains { color in
        color.green == 255
    }
    ok(hasMaxGreenHighlight,
       "NativeMatrixRenderer: palette keeps max-green highlight")

    let r1: NativeMatrixRenderer = .init()
    let r2: NativeMatrixRenderer = .init()
    r1.seedOffset = 0
    r2.seedOffset = 0xDEAD_BEEF
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
    let differ = (0..<20).contains { row in (0..<40).contains { col in r1[row, col] != r2[row, col] } }
    ok(differ, "NativeMatrixRenderer: renderers with different seedOffsets diverge after 60 frames")
}
