import Foundation

public struct CustomError: Error, Decodable {
    var detail: String
}
