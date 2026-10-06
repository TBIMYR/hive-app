import Foundation
import HiveCore

// Prints the state as JSON (for debugging).
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(StateBuilder.build()))
