//
//  Keychain.swift
//  EnvoySDK
//
//

import Foundation
import Security

/**
    Keychain wrapper
*/
final class Keychain: Sendable {
    
    enum Key: String {
        case envoyShareLinkHash = "envoy.share.link.hash"
        case envoyLeadUuid = "envoy.lead.uuid"
    }
    
    static let standard = Keychain()
    
    @discardableResult
    func set(_ value: String, forKey key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        return self.set(data, forKey: key)
    }
    
    func value(forKey key: Key) -> String? {
        guard let data = self.object(forKey: key) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    @discardableResult
    func set(_ data: Data, forKey key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status: OSStatus = SecItemAdd(query as CFDictionary, nil)
        
        return status == noErr
    }
    
    func object(forKey key: Key) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
            let existingItem = item as? Data else {
                return nil
        }
        
        return existingItem
    }
    
    @discardableResult
    func delete(key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status: OSStatus = SecItemDelete(query as CFDictionary)
        
        return status == noErr
    }
    
    @discardableResult
    func clear() -> Bool {
        let query = [
            kSecClass as String: kSecClassGenericPassword
        ]
        
        let status: OSStatus = SecItemDelete(query as CFDictionary)
        
        return status == noErr
    }
}
