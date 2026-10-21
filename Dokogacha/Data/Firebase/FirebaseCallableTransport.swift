//
//  FirebaseCallableTransport.swift
//  Dokogacha
//

@preconcurrency import FirebaseFunctions
import Foundation

/// Cloud Functions の SDK を使う `CallableTransport`。`FirebaseApp.configure` の後でだけ作る
final class FirebaseCallableTransport: CallableTransport {
    private let functions: Functions

    /// 呼び出し口を受け取って作る（既定は東京リージョン。Emulator への接続は `FirebaseBootstrap` で済ませてある）
    init(functions: Functions = FirebaseBootstrap.functions()) {
        self.functions = functions
    }

    func call<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: CallableName,
        _ request: Request,
        responseType: Response.Type
    ) async throws -> Response {
        let callable = functions.httpsCallable(name.rawValue, requestAs: Request.self, responseAs: Response.self)
        do {
            return try await callable.call(request)
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// SDK のエラーを `ServerFailure` にする。
    ///
    /// `HttpsError` は `FunctionsErrorDomain` のエラーで、`code` が gRPC の番号、`userInfo` の `details` に
    /// backend が入れた `{ reason }` が入る。通信できないとき（オフラインなど）は `NSURLErrorDomain` のエラーが来る。
    /// 戻り値をモデルにできなかったとき（`DecodingError`）は `internal` にする
    static func failure(from error: any Error) -> ServerFailure {
        let error = error as NSError
        switch error.domain {
        case FunctionsErrorDomain:
            let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            return ServerFailure(code: ServerErrorCode(grpcCode: error.code), reason: details?["reason"] as? String)
        case NSURLErrorDomain:
            return ServerFailure(code: .unavailable)
        default:
            return ServerFailure(code: .internal)
        }
    }
}
