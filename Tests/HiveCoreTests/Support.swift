import Foundation

/// Copy of hive/test/fixtures (claudeHome for the tests)
let fixtures: String = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.path

func fixture(_ rel: String) -> String { "\(fixtures)/\(rel)" }

let dev = "/Users/dev/Development"
