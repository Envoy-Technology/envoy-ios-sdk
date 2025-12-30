import Foundation

fileprivate struct MappingKeys {
    static let authorization = "x-api-key"
}

protocol GetUserCurrentRewardsServiceType {
    @discardableResult
    func getUserCurrentRewards(
        userId: String,
        completion: @escaping (UserCurrentRewardsResponse?, WebError?) -> ()) -> URLSessionDataTask?
}

final class GetUserCurrentRewardsService {

    private let client: WebClient
    private let apiKey: String

    init(client: WebClient, apiKey: String) {
        self.client = client
        self.apiKey = apiKey
    }
}

extension GetUserCurrentRewardsService: GetUserCurrentRewardsServiceType {
    @discardableResult
    func getUserCurrentRewards(
        userId: String,
        completion: @escaping (UserCurrentRewardsResponse?, WebError?) -> ()) -> URLSessionDataTask? {
        let path = Endpoint.getUserCurrentRewards(userId: userId).path
        let headers = [MappingKeys.authorization : "\(apiKey)"]
        let resource = Resource<UserCurrentRewardsResponse>(
            path: path,
            method: .get,
            headers: headers
        )
        return client.load(resource: resource) { (response) in
//            DispatchQueue.main.async {
                completion(response.value, response.error)
//            }
        }
    }
}
