import Foundation

struct Path {
    private var components: [String]
    private var path: String
    
    var absolutePath: String {
        return "/" + components.joined(separator: "/")
    }
    
    var absoluteURL: String {
        return path
    }
    
    init(_ path: String) {
        self.path = path
        self.components = path.components(separatedBy: "/").filter({ !$0.isEmpty })
    }
    
    mutating func append(path: Path) {
        components += path.components
    }
    
    func appending(path: Path) -> Path {
        var copy = self
        copy.append(path: path)
        return copy
    }
}
