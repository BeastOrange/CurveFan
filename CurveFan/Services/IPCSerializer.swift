import Foundation

public enum IPCSerializer {
    public static func encode(_ command: IPCCommand) throws -> Data {
        try JSONEncoder().encode(command)
    }

    public static func decode(_ data: Data) throws -> IPCResponse {
        try JSONDecoder().decode(IPCResponse.self, from: data)
    }
}