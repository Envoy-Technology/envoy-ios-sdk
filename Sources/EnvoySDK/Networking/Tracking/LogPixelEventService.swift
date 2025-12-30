import Foundation

fileprivate struct MappingKeys {
    static let authorization = "x-api-key"
}

protocol LogPixelEventServiceType {
    @discardableResult
    func logPixelEvent(request: LogPixelEventRequest,
                       completion: @escaping (EmptyResponse?, WebError?) -> ()) -> URLSessionDataTask?
}

final class LogPixelEventService {
    
    private let client: WebClient
    private let apiKey: String
    
    init(client: WebClient, apiKey: String) {
        self.client = client
        self.apiKey = apiKey
    }
}

extension LogPixelEventService: LogPixelEventServiceType {
    @discardableResult
    func logPixelEvent(request: LogPixelEventRequest,
                       completion: @escaping (EmptyResponse?, WebError?) -> ()) -> URLSessionDataTask? {
        let path = Endpoint.logPixelEvent.path
        let headers = [MappingKeys.authorization : "\(apiKey)"]
        let resource = Resource<EmptyResponse>(
            path: path,
            method: .post,
            params: request.asJSON(keyEncodingStrategy: .convertToSnakeCase) ?? [:],
            headers: headers
        )
        return client.load(resource: resource) { (response) in
//            DispatchQueue.main.async {
                completion(response.value, response.error)
//            }
        }
    }
}
