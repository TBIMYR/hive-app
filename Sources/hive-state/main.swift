import Foundation
import HiveCore

// Gibt den Zustand wie GET /api/state aus (zum Vergleich mit dem Node-Server, siehe scripts/compare-node.sh).
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(StateBuilder.build()))
