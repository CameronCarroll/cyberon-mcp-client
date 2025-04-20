# src/errors.cr

# Base class for MCP Client specific errors (optional, but good practice)
class MCPError < Exception; end

# Raised for general runtime problems within the client (e.g., not initialized)
class MCPRuntimeError < MCPError; end

# Raised for invalid arguments or preconditions (e.g., feature not supported)
class MCPValueError < MCPError; end

# Could add more specific errors if needed
# class MCPTimeoutError < MCPError; end
# class MCPConnectionError < MCPError; end
