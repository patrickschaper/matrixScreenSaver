import Foundation

// TAP harness — shared state used by all test files.
var testCount = 0
var failCount = 0

func ok(_ condition: Bool, _ description: String, file: StaticString = #file, line: Int = #line) {
    testCount += 1
    if condition {
        print("ok \(testCount) - \(description)")
    } else {
        print("not ok \(testCount) - \(description)")
        print("  # \(file):\(line)")
        failCount += 1
    }
}

xorshift64Tests()
screenSyncCoordinatorTests()
nativeMatrixRendererTests()

print("1..\(testCount)")
exit(failCount == 0 ? 0 : 1)
