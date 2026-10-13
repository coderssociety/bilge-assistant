import Foundation

/// One reply of the multi-step planner: call a tool, or finish with what to tell the user.
public enum AgentStep: Equatable, Sendable {
    case call(tool: String, argumentsJSON: String)
    case done(String)

    /// Accepts the first JSON object in the reply, so stray text around it does no harm.
    public static func parse(_ reply: String) -> AgentStep? {
        guard let json = firstJSONObject(in: reply),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        if let done = object["done"] as? String { return .done(done) }
        guard let tool = object["tool"] as? String, !tool.isEmpty else { return nil }
        let arguments = object["arguments"] as? [String: Any] ?? [:]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) else { return nil }
        return .call(tool: tool, argumentsJSON: String(decoding: data, as: UTF8.self))
    }

    /// The first balanced {...}, ignoring braces inside strings.
    static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in text[start...].indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            default: break
            }
        }
        return nil
    }
}

/// A one-line signature for a tool's argument schema, e.g.
/// `addCalendarEvent(title: string, dayOffset?: integer 0…60)`: the full JSON schemas of 45 tools
/// would take ~7K tokens of the planner's context.
public enum ToolSignature {
    public static func compact(name: String, schemaJSON: Data) -> String {
        guard let schema = try? JSONSerialization.jsonObject(with: schemaJSON) as? [String: Any],
              let properties = schema["properties"] as? [String: Any] else { return "\(name)()" }
        let required = Set(schema["required"] as? [String] ?? [])
        let order = schema["x-order"] as? [String] ?? properties.keys.sorted()
        let arguments = order.compactMap { key -> String? in
            guard let property = properties[key] as? [String: Any] else { return nil }
            let note = (property["description"] as? String).map { " \"\($0)\"" } ?? ""
            return "\(key)\(required.contains(key) ? "" : "?"): \(type(of: property))\(note)"
        }
        return "\(name)(\(arguments.joined(separator: ", ")))"
    }

    private static func type(of property: [String: Any]) -> String {
        if let values = property["enum"] as? [String] { return values.joined(separator: "|") }
        if let options = property["anyOf"] as? [[String: Any]] {
            let values = options.compactMap { ($0["enum"] as? [String])?.joined(separator: "|") ?? ($0["const"] as? String) }
            if !values.isEmpty { return values.joined(separator: "|") }
        }
        let base = property["type"] as? String ?? "any"
        if let minimum = property["minimum"] as? Int, let maximum = property["maximum"] as? Int { return "\(base) \(minimum)…\(maximum)" }
        return base
    }
}
