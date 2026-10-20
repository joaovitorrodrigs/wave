import SwiftData
import Foundation

@Model final class Client {
    var name: String
    var created = Date.now
    init(name: String) { self.name = name }
}
