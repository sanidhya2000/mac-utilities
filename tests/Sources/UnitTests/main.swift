import Foundation

let harness = Harness()
print("Unit tests — PowerCore + GazeCore")

runGazeModelTests(harness)
runGeometryTests(harness)
runPowerCoreTests(harness)

harness.finish()
