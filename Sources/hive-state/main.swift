import Foundation
import HiveCore

// Prints the state like GET /api/state (for comparison with the Node server, see scripts/compare-node.sh).
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(StateBuilder.build()))
