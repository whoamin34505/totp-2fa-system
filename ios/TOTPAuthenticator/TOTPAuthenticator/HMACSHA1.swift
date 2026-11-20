//
//  HMACSHA1.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 20.11.2026.
//

import Foundation
import CryptoKit

struct HMACSHA1 {
    func calculate(key: Data, message: Data) -> Data {
        var key = key
        if key.count > 64 {
            key = Data(Insecure.SHA1.hash(data: key))
        }
        if key.count < 64 {
            key.append(Data(repeating: 0x00, count: 64 - key.count))
        }
        let ipad = Data(repeating: 0x36, count: 64)
        let opad = Data(repeating: 0x5c, count: 64)
        var xor1 = [UInt8]()
        var xor2 = [UInt8]()
        for i in 0..<64 {
            xor1.append(key[i] ^ ipad[i])
            xor2.append(key[i] ^ opad[i])
        }
        let xor1Data = Data(xor1)
        let xor2Data = Data(xor2)
        let innerHash = Data(Insecure.SHA1.hash(data: xor1Data + message))
        let result = Data(Insecure.SHA1.hash(data: xor2Data + innerHash))
        return result
    }
}
