import Foundation

/// Responses of POST /api/conversation/process, shaped as Home Assistant 2026.10 sends them.
enum HomeAssistantFixtures {
    static let actionDone = Data(#"""
    {"continue_conversation":false,"response":{"speech":{"plain":{"speech":"Salon ışığı açıldı","extra_data":null}},"card":{},"language":"tr","response_type":"action_done","data":{"targets":[],"success":[{"name":"Salon","type":"area","id":"living_room"}],"failed":[]}},"conversation_id":"01JCQ7S3VE5M5W0Y0X3Q2P7J8K"}
    """#.utf8)

    static let noMatch = Data(#"""
    {"continue_conversation":false,"response":{"speech":{"plain":{"speech":"Sorry, I couldn't understand that","extra_data":null}},"card":{},"language":"en","response_type":"error","data":{"code":"no_intent_match"}},"conversation_id":"01JCQ7S3VE5M5W0Y0X3Q2P7J8L"}
    """#.utf8)

    static let silent = Data(#"{"response":{"speech":{},"response_type":"action_done"}}"#.utf8)

    static let status = Data(#"{"message":"API running."}"#.utf8)
}
