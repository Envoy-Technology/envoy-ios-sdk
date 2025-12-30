import Foundation

enum Result<A> {
    case success(A)
    case failure(WebError)
}

extension Result {
    init(value: A?, or error: WebError) {
        guard let value = value else {
            self = .failure(error)
            return
        }
        
        self = .success(value)
    }
    
    var value: A? {
        guard case let .success(value) = self else { return nil }
        return value
    }
    
    var error: WebError? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
