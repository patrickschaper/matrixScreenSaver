/// Validation limits shared between NativeMatrixRenderer and MatrixScreenSaverOptions.
/// Foundation-only so this file can be compiled without AppKit or ScreenSaver.framework.
enum MatrixRendererLimits {
    static let minimumRainDensity: Double = 0.0001
    static let minimumFrameRate: Double = 0.0001
    static let maximumFrameRate: Double = 1000.0
    static let minimumErrorRate: Double = 0.0
    static let minimumNeoMessageSpeedFactor: Double = 0.0001
}
