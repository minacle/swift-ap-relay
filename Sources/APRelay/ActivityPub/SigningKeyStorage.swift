import _CryptoExtras
import Vapor

private struct SigningKeyStorageKey: StorageKey {
    typealias Value = _RSA.Signing.PrivateKey
}

extension Application {
    /// The RSA private key used for HTTP signature signing.
    var signingKey: _RSA.Signing.PrivateKey {
        get {
            guard let key = storage[SigningKeyStorageKey.self] else {
                fatalError("Signing key not configured. Call configure() first.")
            }
            return key
        }
        set {
            storage[SigningKeyStorageKey.self] = newValue
        }
    }
}
