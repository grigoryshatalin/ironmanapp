import Foundation

/// Encodes/decodes `TrainingPlanDefinition` to and from JSON, mapping the raw
/// `DecodingError` into an actionable message (§15 "Reject malformed plans with
/// actionable errors rather than crashing").
public enum PlanCodec {

    public struct DecodeFailure: Error, Sendable, Equatable, CustomStringConvertible {
        public var message: String
        public var codingPath: String?
        public var description: String {
            if let p = codingPath, !p.isEmpty { return "\(message) (at \(p))" }
            return message
        }
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decode(_ data: Data) throws -> TrainingPlanDefinition {
        do {
            return try makeDecoder().decode(TrainingPlanDefinition.self, from: data)
        } catch let error as DecodingError {
            throw mapDecodingError(error)
        }
    }

    public static func encode(_ plan: TrainingPlanDefinition) throws -> Data {
        try makeEncoder().encode(plan)
    }

    private static func mapDecodingError(_ error: DecodingError) -> DecodeFailure {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let ctx):
            return DecodeFailure(message: "Missing required field '\(key.stringValue)'.", codingPath: path(ctx))
        case .typeMismatch(let type, let ctx):
            return DecodeFailure(message: "Field has the wrong type; expected \(type).", codingPath: path(ctx))
        case .valueNotFound(let type, let ctx):
            return DecodeFailure(message: "Required value of type \(type) was null.", codingPath: path(ctx))
        case .dataCorrupted(let ctx):
            return DecodeFailure(message: ctx.debugDescription, codingPath: path(ctx))
        @unknown default:
            return DecodeFailure(message: "The plan file could not be read.", codingPath: nil)
        }
    }
}
