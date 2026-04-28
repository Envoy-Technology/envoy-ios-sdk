import Foundation

public struct ManageLinksRequest: Encodable {
    let links: [String]

    public init(links: [String]) {
        self.links = links
    }
}
