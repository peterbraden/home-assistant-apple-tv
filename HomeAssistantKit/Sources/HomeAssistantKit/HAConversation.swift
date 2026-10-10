import Foundation

/// Home Assistant's reply to a sentence sent to Assist (`conversation/process`).
public struct HAConversationResponse: Sendable, Hashable {
    public enum Kind: String, Sendable {
        case actionDone = "action_done"
        case queryAnswer = "query_answer"
        case error
    }

    /// What Assist would say out loud.
    public let speech: String
    public let kind: Kind?
    /// Pass back with the next sentence to continue the same conversation.
    public let conversationId: String?
    /// True when Assist asked a question and expects an answer.
    public let continueConversation: Bool
    /// Entities the command acted on successfully.
    public let changedEntityIds: [String]

    public init(_ json: JSONValue) {
        let response = json["response"]
        speech = response?["speech"]?["plain"]?["speech"]?.stringValue ?? ""
        kind = response?["response_type"]?.stringValue.flatMap(Kind.init)
        conversationId = json["conversation_id"]?.stringValue
        continueConversation = json["continue_conversation"]?.boolValue ?? false
        changedEntityIds = (response?["data"]?["success"]?.arrayValue ?? [])
            .compactMap { $0["type"]?.stringValue == "entity" ? $0["id"]?.stringValue : nil }
    }
}

/// An Assist pipeline: which conversation agent and language to use.
public struct HAAssistPipeline: Sendable, Hashable {
    public let id: String
    public let name: String
    public let conversationEngine: String?
    public let language: String?

    /// The preferred pipeline from an `assist_pipeline/pipeline/list` result.
    public static func preferred(from json: JSONValue) -> HAAssistPipeline? {
        let pipelines = all(from: json)
        let preferredID = json["preferred_pipeline"]?.stringValue
        return pipelines.first { $0.id == preferredID } ?? pipelines.first
    }

    /// Every pipeline in an `assist_pipeline/pipeline/list` result.
    public static func all(from json: JSONValue) -> [HAAssistPipeline] {
        (json["pipelines"]?.arrayValue ?? []).compactMap { item -> HAAssistPipeline? in
            guard let id = item["id"]?.stringValue else { return nil }
            return HAAssistPipeline(
                id: id,
                name: item["name"]?.stringValue ?? id,
                conversationEngine: item["conversation_engine"]?.stringValue,
                language: item["conversation_language"]?.stringValue
            )
        }
    }
}
