import Foundation

fileprivate struct MappingKeys {
    static let authorization = "x-api-key"
}

protocol PrepLinkServiceType {
    @discardableResult
    func prepLink(
        request: PrepLinkRequest,
        completion: @escaping (PrepLinkResponse?, WebError?) -> ()
    ) -> URLSessionDataTask?
}

final class PrepLinkService {

    private let client: WebClient
    private let apiKey: String

    init(
        client: WebClient,
        apiKey: String
    ) {
        self.client = client
        self.apiKey = apiKey
    }
}

extension PrepLinkService: PrepLinkServiceType {
    @discardableResult
    func prepLink(
        request: PrepLinkRequest,
        completion: @escaping (PrepLinkResponse?, WebError?) -> ()
    ) -> URLSessionDataTask? {
        let path = Endpoint.prepLink.path
        let headers = [MappingKeys.authorization : "\(apiKey)"]
        let resource = Resource<PrepLinkResponse>(
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
