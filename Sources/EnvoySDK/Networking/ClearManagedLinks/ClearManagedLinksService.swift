import Foundation

fileprivate struct MappingKeys {
    static let authorization = "x-api-key"
}

protocol ClearManagedLinksServiceType {
    @discardableResult
    func clearManagedLinks(
        completion: @escaping (ClearManagedLinksResponse?, WebError?) -> ()
    ) -> URLSessionDataTask?
}

final class ClearManagedLinksService {

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

extension ClearManagedLinksService: ClearManagedLinksServiceType {
    @discardableResult
    func clearManagedLinks(
        completion: @escaping (ClearManagedLinksResponse?, WebError?) -> ()
    ) -> URLSessionDataTask? {
        let path = Endpoint.clearManagedLinks.path
        let headers = [MappingKeys.authorization : "\(apiKey)"]
        let resource = Resource<ClearManagedLinksResponse>(
            path: path,
            method: .post,
            params: [:],
            headers: headers
        )
        return client.load(resource: resource) { (response) in
//            DispatchQueue.main.async {
                completion(response.value, response.error)
//            }
        }
    }
}
