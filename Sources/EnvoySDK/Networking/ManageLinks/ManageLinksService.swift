import Foundation

fileprivate struct MappingKeys {
    static let authorization = "x-api-key"
}

protocol ManageLinksServiceType {
    @discardableResult
    func manageLinks(
        request: ManageLinksRequest,
        completion: @escaping (ManageLinksResponse?, WebError?) -> ()
    ) -> URLSessionDataTask?
}

final class ManageLinksService {

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

extension ManageLinksService: ManageLinksServiceType {
    @discardableResult
    func manageLinks(
        request: ManageLinksRequest,
        completion: @escaping (ManageLinksResponse?, WebError?) -> ()
    ) -> URLSessionDataTask? {
        let path = Endpoint.manageLinks.path
        let headers = [MappingKeys.authorization : "\(apiKey)"]
        let resource = Resource<ManageLinksResponse>(
            path: path,
            method: .post,
            params: request.asJSON(keyEncodingStrategy: .useDefaultKeys) ?? [:],
            headers: headers
        )
        return client.load(resource: resource) { (response) in
//            DispatchQueue.main.async {
                completion(response.value, response.error)
//            }
        }
    }
}
