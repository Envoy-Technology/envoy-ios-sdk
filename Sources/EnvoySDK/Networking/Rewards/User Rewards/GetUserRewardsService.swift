import Foundation

fileprivate struct MappingKeys {
    static let authorization = "x-api-key"
}

protocol GetUserRewardsServiceType {
    @discardableResult
    func getUserRewards(userId: String,
                        completion: @escaping (UserRewardsResponse?, WebError?) -> ()) -> URLSessionDataTask?
}

final class GetUserRewardsService {

    private let client: WebClient
    private let apiKey: String

    init(client: WebClient, apiKey: String) {
        self.client = client
        self.apiKey = apiKey
    }
}

extension GetUserRewardsService: GetUserRewardsServiceType {
    @discardableResult
    func getUserRewards(userId: String,
                        completion: @escaping (UserRewardsResponse?, WebError?) -> ()) -> URLSessionDataTask? {
        let path = Endpoint.getUserRewards(userId: userId).path
        let headers = [MappingKeys.authorization : "\(apiKey)"]
        let resource = Resource<UserRewardsResponse>(
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
