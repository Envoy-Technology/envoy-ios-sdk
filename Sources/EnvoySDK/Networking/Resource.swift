import Foundation

struct Resource<A> {
    let path: Path
    let method: RequestMethod
    var headers: HTTPHeaders
    var params: JSON
    let parse: (Data) -> A?
    let parseError: (Data) -> CustomError?
    var isAbsolutePath = false
    
    init(path: String,
         method: RequestMethod = .get,
         params: JSON = [:],
         headers: HTTPHeaders = [:],
         isAbsolutePath: Bool = false,
         parse: @escaping (Data) -> A?,
         parseError: @escaping (Data) -> CustomError?) {
        
        self.path = Path(path)
        self.method = method
        self.params = params
        self.headers = headers
        self.parse = parse
        self.parseError = parseError
        self.isAbsolutePath = isAbsolutePath
    }
}

extension Resource where A: Decodable {
    init(jsonDecoder: JSONDecoder = JSONDecoder.defaultDecoder,
         path: String,
         method: RequestMethod = .get,
         params: JSON = [:],
         headers: HTTPHeaders = [:],
         isAbsolutePath: Bool = false,
         parse: ((Data) -> A?)? = nil,
         parseError: ((Data) -> CustomError?)? = nil) {
        var newHeaders = headers
        newHeaders["Accept"] = "application/json"
        newHeaders["Content-Type"] = "application/json"
        
        self.path = Path(path)
        self.method = method
        self.params = params
        self.headers = newHeaders
        self.isAbsolutePath = isAbsolutePath
        self.parse = parse ?? { try? jsonDecoder.decode(A.self, from: $0) }
        self.parseError = parseError ?? { try? jsonDecoder.decode(CustomError.self, from: $0) }
    }
}
