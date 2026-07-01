import Foundation

public enum IPCSerializer {
    public static let protocolVersion = 1

    /// Wire versions the helper will accept. 0 is the legacy raw-IPCCommand
    /// format (no envelope); anything >= 1 is a versioned envelope.
    public static let compatibleVersions: Set<Int> = [0, 1]

    /// Returns true if `version` is one this build will dispatch. The helper
    /// invokes this before running any command so an unknown future client
    /// receives an explicit rejection instead of having its command silently
    /// dispatched as if it were v1.
    public static func isCompatibleVersion(_ version: Int) -> Bool {
        compatibleVersions.contains(version)
    }

    public static func encode(_ command: IPCCommand) throws -> Data {
        let cmdData = try JSONEncoder().encode(command)
        guard let cmdObject = try JSONSerialization.jsonObject(with: cmdData) as? [String: Any] else {
            throw IPCError.invalidFrame("command was not a JSON object")
        }
        let envelope: [String: Any] = [
            "v": protocolVersion,
            "cmd": cmdObject
        ]
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    public static func decode(_ data: Data) throws -> IPCResponse {
        try JSONDecoder().decode(IPCResponse.self, from: data)
    }

    /// Decode an incoming request as either a v1 envelope `{v:1, cmd:{...}}` or
    /// a raw IPCCommand (legacy wire format). Returns the parsed command plus
    /// the protocol version of the envelope (0 when raw/legacy).
    public static func decodeRequest(_ data: Data) throws -> (command: IPCCommand, version: Int) {
        if let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = envelope["cmd"],
           JSONSerialization.isValidJSONObject(raw) {
            let cmdData = try JSONSerialization.data(withJSONObject: raw)
            let command = try JSONDecoder().decode(IPCCommand.self, from: cmdData)
            let version = (envelope["v"] as? Int) ?? 0
            return (command, version)
        }
        let command = try JSONDecoder().decode(IPCCommand.self, from: data)
        return (command, 0)
    }
}