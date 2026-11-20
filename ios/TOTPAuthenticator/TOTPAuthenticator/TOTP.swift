//
//  TOTP.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 20.11.2026.
//

import Foundation

struct TOTP {

    func generate(key: Data) -> String {
        let timestamp = Date().timeIntervalSince1970
        let counter = UInt64(timestamp / 30)
        return HOTP().generate(key: key, counter: counter)
    }
}
