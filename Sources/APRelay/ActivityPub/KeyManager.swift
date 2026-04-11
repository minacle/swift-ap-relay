import Crypto
import _CryptoExtras
import Foundation

/// Manages RSA key pair generation, storage, and retrieval.
struct KeyManager: Sendable {
    private let repository: any RelayRepository

    init(repository: any RelayRepository) {
        self.repository = repository
    }

    /// Retrieves the existing private key from the repository, or generates and stores a new one.
    func getOrCreatePrivateKey() async throws -> _RSA.Signing.PrivateKey {
        if let pem = try await repository.getSetting(key: "rsa_private_key_pem") {
            return try _RSA.Signing.PrivateKey(pemRepresentation: pem)
        }

        let privateKey = try _RSA.Signing.PrivateKey(keySize: .bits4096)
        let privatePEM = privateKey.pemRepresentation
        let publicPEM = privateKey.publicKey.pemRepresentation

        try await repository.setSetting(key: "rsa_private_key_pem", value: privatePEM)
        try await repository.setSetting(key: "rsa_public_key_pem", value: publicPEM)

        return privateKey
    }

    /// Retrieves the public key PEM string.
    func getPublicKeyPEM() async throws -> String {
        if let pem = try await repository.getSetting(key: "rsa_public_key_pem") {
            return pem
        }
        let privateKey = try await getOrCreatePrivateKey()
        return privateKey.publicKey.pemRepresentation
    }
}
