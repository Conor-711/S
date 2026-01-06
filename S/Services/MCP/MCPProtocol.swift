import Foundation

// MARK: - MCP (Model Context Protocol) Interface
// Reference: https://developers.notion.com/docs/get-started-with-mcp

// MARK: - MCP Client Protocol

/// Protocol for MCP server communication
protocol MCPClientProtocol: Sendable {
    /// Server identifier
    var serverName: String { get }
    
    /// Connection status
    var isConnected: Bool { get async }
    
    /// Connect to the MCP server
    func connect() async throws
    
    /// Disconnect from the MCP server
    func disconnect() async
    
    /// List available tools on the server
    func listTools() async throws -> [MCPTool]
    
    /// Execute a tool with arguments
    func executeTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult
}

// MARK: - MCP Data Structures

/// MCP Tool Definition
struct MCPTool: Codable, Sendable, Identifiable {
    let name: String
    let description: String?
    let inputSchema: MCPInputSchema?
    
    var id: String { name }
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

/// JSON Schema for tool input
struct MCPInputSchema: Codable, Sendable {
    let type: String
    let properties: [String: MCPPropertySchema]?
    let required: [String]?
}

/// Property schema definition
struct MCPPropertySchema: Codable, Sendable {
    let type: String
    let description: String?
    let enumValues: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
}

/// MCP Tool Execution Result
struct MCPToolResult: Sendable {
    let success: Bool
    let content: String?
    let error: String?
    let metadata: [String: String]?
    
    static func success(_ content: String, metadata: [String: String]? = nil) -> MCPToolResult {
        MCPToolResult(success: true, content: content, error: nil, metadata: metadata)
    }
    
    static func failure(_ error: String) -> MCPToolResult {
        MCPToolResult(success: false, content: nil, error: error, metadata: nil)
    }
}

// MARK: - MCP Tool Request

/// Request to execute an MCP tool
struct MCPToolRequest: Sendable {
    let serverName: String
    let toolName: String
    let arguments: [String: Any]
    
    init(serverName: String, toolName: String, arguments: [String: Any]) {
        self.serverName = serverName
        self.toolName = toolName
        self.arguments = arguments
    }
}

// MARK: - MCP JSON-RPC Messages (Streamable HTTP Protocol)

/// JSON-RPC Request structure
struct MCPJSONRPCRequest: Codable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: [String: AnyCodable]?
    
    init(id: String = UUID().uuidString, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC Response structure
struct MCPJSONRPCResponse: Codable {
    let jsonrpc: String
    let id: String?
    let result: AnyCodable?
    let error: MCPJSONRPCError?
}

/// JSON-RPC Error structure
struct MCPJSONRPCError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper
struct AnyCodable: Codable, Sendable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Cannot encode AnyCodable")
            throw EncodingError.invalidValue(value, context)
        }
    }
}

// MARK: - MCP Connection State

enum MCPConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case authenticating
    case error(String)
    
    static func == (lhs: MCPConnectionState, rhs: MCPConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.authenticating, .authenticating):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

// MARK: - MCP Session Info

struct MCPSessionInfo: Sendable {
    let sessionId: String
    let serverName: String
    let capabilities: [String]
    let connectedAt: Date
}
