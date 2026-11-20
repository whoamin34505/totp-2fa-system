//
//  HOTP.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 20.11.2026.
//

import Foundation

struct HOTP {

    func generate(key: Data, counter: UInt64) -> String {
        var bigEndianCounter = counter.bigEndian
        let hs = withUnsafeBytes(of: &bigEndianCounter) {
            HMACSHA1().calculate(key: key, message: Data($0))
        }
        let offset = Int(hs[19] & 0x0F)
        let selectedBytes = Array(hs[offset..<(offset + 4)])
        let binaryCode =
            (UInt32(selectedBytes[0] & 0x7F) << 24) |
            (UInt32(selectedBytes[1]) << 16) |
            (UInt32(selectedBytes[2]) << 8) |
            UInt32(selectedBytes[3])
        let code = binaryCode % 1000000
        let result = String(format: "%06d", code)
        return result
    }
}
