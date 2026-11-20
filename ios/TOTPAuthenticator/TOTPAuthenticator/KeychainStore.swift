//
//  KeychainStore.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 18.11.2026.
//

import Foundation
import Security

struct KeychainStore {
    func saveSecret(_ secret: String, accountID: String) -> Bool {
        let secretData = Data(secret.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: accountID,
            kSecValueData as String: secretData,
            kSecAttrService as String:"TOTPAuthenticator",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            print("Секрет сохранён")
            return true
        } else {
            print("Ошибка сохранения: \(status)")
            return false
        }
    }
    
    func readSecret(accountID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: accountID,
            kSecReturnData as String: true,
            kSecAttrService as String:"TOTPAuthenticator",
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            if let secretData = result as? Data {
                let secret = String(data: secretData, encoding: .utf8)
                return secret
            }
        }
        print("Секрет не получен: \(status)")
        return nil
    }
    
    func deleteSecret(accountID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String:"TOTPAuthenticator",
            kSecAttrAccount as String: accountID
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("Запись успешно удалена")
        } else if status == errSecItemNotFound {
            print("Запись не найдена")
        } else {
            print("Ошибка: \(status)")
        }
    }
    
    func updateSecret(_ newSecret: String, accountID: String) {
        let secretData = Data(newSecret.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "TOTPAuthenticator",
            kSecAttrAccount as String: accountID
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: secretData,
        ]
        
        let status = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        
        if status == errSecSuccess {
            print("Секрет обновлен")
        } else if status == errSecItemNotFound {
            print("Запись не найдена")
        } else {
            print("Ошибка обновления: \(status)")
        }
    }
    
}
