import Foundation

protocol AppSigning {
    func sign(
        request: SigningRequest,
        progress: @escaping @Sendable (SigningState) -> Void
    ) async throws -> SignedArtifact
}

enum SigningServiceError: LocalizedError {
    case implementationPending

    var errorDescription: String? {
        switch self {
        case .implementationPending:
            return "Zsign bridge is not enabled in v0.1; interface and state machine only."
        }
    }
}

final class AppSigningService: AppSigning {
    func sign(
        request: SigningRequest,
        progress: @escaping @Sendable (SigningState) -> Void
    ) async throws -> SignedArtifact {
        progress(.prepareContext)
        throw SigningServiceError.implementationPending
    }
}
