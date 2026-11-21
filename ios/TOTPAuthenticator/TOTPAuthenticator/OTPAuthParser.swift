
import Foundation

struct ParsedOTPAuth {
    let service: String
    let login: String
    let secret: String
}

struct OTPAuthParser {

    func parse(_ payload: String) -> ParsedOTPAuth? {

        // 1. Разбираем ссылку
        guard let components = URLComponents(string: payload),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              let items = components.queryItems else {
            return nil
        }

        // 2. Проверяем, что важные параметры не повторяются
        let keys = ["secret", "issuer", "algorithm", "digits", "period"]

        for key in keys {
            if items.filter({ $0.name == key }).count > 1 {
                return nil
            }
        }

        // 3. Функция для получения параметра по имени
        func parameter(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        // 4. Получаем и проверяем секрет
        guard let rawSecret = parameter("secret") else {
            return nil
        }

        let secret = rawSecret
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !secret.isEmpty,
              let decoded = Base32Decoder().decode(secret),
              !decoded.isEmpty else {
            return nil
        }

        // 5. Проверяем параметры TOTP
        guard (parameter("algorithm") ?? "SHA1").uppercased() == "SHA1",
              (parameter("digits") ?? "6") == "6",
              (parameter("period") ?? "30") == "30" else {
            return nil
        }

        // 6. Получаем название аккаунта из пути
        guard components.path.hasPrefix("/") else {
            return nil
        }

        let label = String(components.path.dropFirst())

        guard !label.isEmpty else {
            return nil
        }

        // 7. Разделяем "GitHub:kolyan"
        let parts = label.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let labelIssuer: String?
        let login: String

        if parts.count == 2 {
            labelIssuer = parts[0]
            login = parts[1]
        } else {
            labelIssuer = nil
            login = parts[0]
        }

        guard !login.isEmpty else {
            return nil
        }

        if let labelIssuer, labelIssuer.isEmpty {
            return nil
        }

        // 8. Получаем название сервиса
        let issuer = parameter("issuer")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let issuer, issuer.isEmpty {
            return nil
        }

        // Если issuer указан дважды, значения должны совпадать
        if let issuer, let labelIssuer, issuer != labelIssuer {
            return nil
        }

        let service = issuer ?? labelIssuer ?? "Без названия"

        // 9. Возвращаем готовые данные
        return ParsedOTPAuth(
            service: service,
            login: login,
            secret: secret
        )
    }
}
