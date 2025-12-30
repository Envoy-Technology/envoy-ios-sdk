import Foundation

typealias JSON = [String: Any]
typealias HTTPHeaders = [String: String]

enum RequestMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

extension URL {
    init<A>(baseUrl: String, resource: Resource<A>) {
        var components = URLComponents(string: baseUrl)!
        let resourceComponents = URLComponents(string: resource.path.absolutePath)!
        
        components.path = Path(components.path).appending(path: Path(resourceComponents.path)).absolutePath
        components.queryItems = resourceComponents.queryItems
        
        switch resource.method {
        case .get, .delete:
            var queryItems = components.queryItems ?? []
            queryItems.append(contentsOf: resource.params.map {
                URLQueryItem(name: $0.key, value: String(describing: $0.value))
            })
            components.queryItems = queryItems
        default:
            break
        }
        
        self = components.url!
    }
}

extension URLRequest {
    init<A>(baseUrl: String, resource: Resource<A>) {
        var url: URL!
        if resource.isAbsolutePath {
            url = URL(string: resource.path.absoluteURL)
        } else {
            url = URL(baseUrl: baseUrl, resource: resource)
        }
        self.init(url: url)
        httpMethod = resource.method.rawValue
        resource.headers.forEach{
            setValue($0.value, forHTTPHeaderField: $0.key)
        }
        switch resource.method {
        case .post, .put:
            httpBody = try! JSONSerialization.data(withJSONObject: resource.params, options: [])
        default:
            break
        }
    }
}

class WebClient {
    private let baseUrl: String
    
    var commonParams: JSON = [:]
    
    init(baseURL: String) {
        self.baseUrl = baseURL
    }
    
    func load<A>(
        resource: Resource<A>,
        completion: @escaping (Result<A>) ->()
    ) -> URLSessionDataTask? {
        
        var newResource = resource
        newResource.params = newResource.params.merging(commonParams) { spec, common in
            return spec
        }
        
        let request = URLRequest(baseUrl: baseUrl, resource: newResource)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            // Parsing incoming data
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(.other))
                return
            }
                        
            if (200..<300) ~= response.statusCode {
                if let empty = EmptyResponse() as? A {
                    completion(.success(empty))
                } else {
                    completion(Result(value: data.flatMap(resource.parse), or: .decodingError))
                }
            } else if response.statusCode == 401 {
                completion(.failure(.unauthorized))
            } else {
                completion(.failure(data.flatMap(resource.parseError).map({.custom($0)}) ?? .other))
            }
        }
        
        task.resume()
        
        return task
    }
}
