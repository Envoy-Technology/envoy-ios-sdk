import Foundation

public enum WebError: Error {
    case noInternetConnection
    case custom(CustomError)
    case unauthorized
    case other
    case decodingError
}

extension WebError {
    public var message: String {
        switch self {
        case .noInternetConnection:
            return "No Internet Connection"
        case let .custom(error):
            return error.detail
        case .unauthorized:
            return "Unauthorized"
        case .other:
            return "Unexpected error"
        case .decodingError:
            return "Decoding error"
        }
    }
}
