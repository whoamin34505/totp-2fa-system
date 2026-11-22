//
//  TOTPAuthenticatorTests.swift
//  TOTPAuthenticatorTests
//
//  Created by whoamin on 10.11.2026.
//

import Foundation
import Testing
@testable import TOTPAuthenticator

struct TOTPAuthenticatorTests {

    @Test func hotpRFC4226() {
        let key = Data("12345678901234567890".utf8)
        let expected = ["755224", "287082", "359152", "969429", "338314",
                        "254676", "287922", "162583", "399871", "520489"]

        for (counter, code) in expected.enumerated() {
            #expect(HOTP().generate(key: key, counter: UInt64(counter)) == code)
        }
    }

    @Test func totpUsesCurrentTimeStep() {
        let key = Data("12345678901234567890".utf8)
        let before = UInt64(Date().timeIntervalSince1970 / 30)
        let code = TOTP().generate(key: key)
        let after = UInt64(Date().timeIntervalSince1970 / 30)

        #expect(code == HOTP().generate(key: key, counter: before) ||
                code == HOTP().generate(key: key, counter: after))
    }

    @Test func decodeBase32() {
        #expect(Base32Decoder().decode("MZXW6===") == Data("foo".utf8))
        #expect(Base32Decoder().decode("mzxw6") == Data("foo".utf8))
        #expect(Base32Decoder().decode("MZXW6!") == nil)
        #expect(Base32Decoder().decode("MZXW6=") == nil)
    }

    @Test func parseOTPAuth() throws {
        let uri = "otpauth://totp/Example:kolya?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA1&digits=6&period=30"
        let account = try #require(OTPAuthParser().parse(uri))
        #expect(account.service == "Example")
        #expect(account.login == "kolya")
        #expect(account.secret == "JBSWY3DPEHPK3PXP")
    }

    @Test func rejectInvalidOTPAuth() {
        let invalidURIs = [
            "otpauth://hotp/Example:kolya?secret=JBSWY3DPEHPK3PXP",
            "otpauth://totp/Example:kolya?secret=invalid!",
            "otpauth://totp/Example:kolya?secret=JBSWY3DPEHPK3PXP&digits=8",
            "otpauth://totp/Example:kolya?secret=JBSWY3DPEHPK3PXP&issuer=Other",
            "otpauth://totp/Example:kolya?secret=JBSWY3DPEHPK3PXP&secret=JBSWY3DPEHPK3PXP"
        ]
        for uri in invalidURIs {
            #expect(OTPAuthParser().parse(uri) == nil)
        }
    }

}
