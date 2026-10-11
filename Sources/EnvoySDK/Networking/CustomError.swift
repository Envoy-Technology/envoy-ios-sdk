import Foundation

public struct CustomError: Error, Decodable {
    public var detail: String
}
