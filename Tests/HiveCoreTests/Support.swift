import Foundation

/// Kopie von hive/test/fixtures (claudeHome für die Tests)
let fixtures: String = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.path

func fixture(_ rel: String) -> String { "\(fixtures)/\(rel)" }

let dev = "/Users/dev/Development"
