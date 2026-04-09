import Crypto
import _CryptoExtras
import Fluent
import Foundation

/// Manages RSA key pair generation, storage, and retrieval.
struct KeyManager: Sendable {
    private let db: any Database

    init(db: any Database) {
        self.db = db
    }

    /// Retrieves the existing private key from the database, or generates and stores a new one.
    func getOrCreatePrivateKey() async throws -> _RSA.Signing.PrivateKey {
        if let pem = try await RelaySetting.get(key: "rsa_private_key_pem", on: db) {
            return try _RSA.Signing.PrivateKey(pemRepresentation: pem)
        }

        let privateKey = try _RSA.Signing.PrivateKey(keySize: .bits4096)
        let privatePEM = privateKey.pemRepresentation
        let publicPEM = privateKey.publicKey.pemRepresentation

        try await RelaySetting.set(key: "rsa_private_key_pem", value: privatePEM, on: db)
        try await RelaySetting.set(key: "rsa_public_key_pem", value: publicPEM, on: db)

        return privateKey
    }

    /// Retrieves the public key PEM string.
    func getPublicKeyPEM() async throws -> String {
        if let pem = try await RelaySetting.get(key: "rsa_public_key_pem", on: db) {
            return pem
        }
        // Generate keys if they don't exist yet.
        let privateKey = try await getOrCreatePrivateKey()
        return privateKey.publicKey.pemRepresentation
    }
}
