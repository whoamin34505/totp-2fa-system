//
//  Base32Decoder.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 18.11.2026.
//

import Foundation

struct Base32Decoder {
    func decode(_ encodedString: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

        var buffer = 0
        var bitsCount = 0
        var result = Data()

        var normalized = encodedString.uppercased()
        let originalLength = normalized.count

        while normalized.last == "=" {
            normalized.removeLast()
        }

        let paddingCount = originalLength - normalized.count
        let remainder = normalized.count % 8

        guard !normalized.isEmpty,
              [0, 2, 4, 5, 7].contains(remainder) else {
            return nil
        }

        if paddingCount > 0 {
            let expectedPadding = (8 - remainder) % 8

            if paddingCount != expectedPadding {
                return nil
            }
        }

        for letter in normalized {
            guard let index = alphabet.firstIndex(of: letter) else {
                return nil
            }

            buffer = (buffer << 5) | index
            bitsCount += 5

            if bitsCount >= 8 {
                let byte = UInt8(buffer >> (bitsCount - 8))
                result.append(byte)

                bitsCount -= 8
                buffer &= (1 << bitsCount) - 1
            }
        }

        guard buffer == 0 else {
            return nil
        }

        return result
    }
}
