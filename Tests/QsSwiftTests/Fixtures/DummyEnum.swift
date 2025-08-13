/// DummyEnum is a simple enumeration used for testing purposes.
enum DummyEnum: String, CaseIterable, CustomStringConvertible {
    case lorem = "LOREM"
    case ipsum = "IPSUM"
    case dolor = "DOLOR"

    var description: String {
        return self.rawValue
    }
}

