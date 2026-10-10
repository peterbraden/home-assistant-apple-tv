import Foundation
import Testing
@testable import HomeAssistantKit

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@Suite struct ConversationTests {
    @Test func parsesActionResponse() throws {
        let response = HAConversationResponse(try json(#"""
        {"response": {"speech": {"plain": {"speech": "Turned on the light", "extra_data": null}},
                      "card": {}, "language": "en", "response_type": "action_done",
                      "data": {"targets": [], "success": [
                        {"name": "Office", "type": "area", "id": "office"},
                        {"name": "Office light", "type": "entity", "id": "light.office"}], "failed": []}},
         "conversation_id": "01ABC", "continue_conversation": false}
        """#))
        #expect(response.speech == "Turned on the light")
        #expect(response.kind == .actionDone)
        #expect(response.conversationId == "01ABC")
        #expect(!response.continueConversation)
        #expect(response.changedEntityIds == ["light.office"])
    }

    @Test func parsesErrorResponse() throws {
        let response = HAConversationResponse(try json(#"""
        {"response": {"speech": {"plain": {"speech": "Sorry, I am not aware of any device called kettle"}},
                      "response_type": "error", "data": {"code": "no_valid_targets"}},
         "conversation_id": null, "continue_conversation": true}
        """#))
        #expect(response.kind == .error)
        #expect(response.conversationId == nil)
        #expect(response.continueConversation)
        #expect(response.changedEntityIds.isEmpty)
    }

    @Test func picksPreferredPipeline() throws {
        let result = try json(#"""
        {"pipelines": [
           {"id": "a", "name": "Home Assistant", "conversation_engine": "conversation.home_assistant",
            "conversation_language": "en"},
           {"id": "b", "name": "Claude", "conversation_engine": "conversation.claude", "conversation_language": "*"}],
         "preferred_pipeline": "b"}
        """#)
        let pipeline = try #require(HAAssistPipeline.preferred(from: result))
        #expect(pipeline.name == "Claude")
        #expect(pipeline.conversationEngine == "conversation.claude")
        #expect(HAAssistPipeline.all(from: result).map(\.id) == ["a", "b"])
        #expect(HAAssistPipeline.preferred(from: try json(#"{"pipelines": []}"#)) == nil)
    }
}
