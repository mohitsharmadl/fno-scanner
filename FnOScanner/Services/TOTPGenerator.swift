import Foundation
import CryptoKit

struct TOTPGenerator {
    static func generate(secret: String, period: Int = 30, digits: Int = 6) -> String? {
        guard let secretData = base32Decode(secret.uppercased().filter({ $0 != "=" && $0 != " " })) else {
            return nil
        }

        let counter = UInt64(Date().timeIntervalSince1970) / UInt64(period)
        var bigEndianCounter = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }

        let key = SymmetricKey(data: secretData)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hmacBytes = Array(hmac)

        let offset = Int(hmacBytes[hmacBytes.count - 1] & 0x0f)
        let code = (Int(hmacBytes[offset]) & 0x7f) << 24
                 | (Int(hmacBytes[offset + 1]) & 0xff) << 16
                 | (Int(hmacBytes[offset + 2]) & 0xff) << 8
                 | (Int(hmacBytes[offset + 3]) & 0xff)

        let otp = code % Int(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }

    private static func base32Decode(_ input: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

        var bits = 0
        var buffer = 0
        var bytes: [UInt8] = []

        for char in input {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            let value = alphabet.distance(from: alphabet.startIndex, to: index)
            buffer = (buffer << 5) | value
            bits += 5

            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> bits) & 0xff))
            }
        }

        return bytes.isEmpty ? nil : Data(bytes)
    }
}
