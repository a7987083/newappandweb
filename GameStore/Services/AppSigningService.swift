import Foundation

protocol AppSigning {
    func sign(
        request: SigningRequest,
        progress: @escaping (SigningState) -> Void,
        completion: @escaping (Result<SignedArtifact, Error>) -> Void
    )
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
        progress: @escaping (SigningState) -> Void,
        completion: @escaping (Result<SignedArtifact, Error>) -> Void
    ) {
        progress(.prepareContext)
        completion(.failure(SigningServiceError.implementationPending))
    }
}
