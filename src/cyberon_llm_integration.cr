# src/cyberon_llm_integration.cr
require "json"
require "./mcp_client"
require "./transport"
require "./_tool_processor"

class CyberonLLMIntegration
  # Client instance
  getter client : CyberonMCP::Client

  # Initialize integration with MCP server path
  def initialize(server_path : String, use_shell : Bool = false)
    # Create transport pointing to the MCP server
    @transport = CyberonMCP::ProcessTransport.new(server_path, use_shell)

    # Create and initialize client
    @client = CyberonMCP::Client.new(@transport)

    # Launch the server
    @transport.launch_server

    # Initialize connection
    @client.init_connection
  end

  # Initialize with an existing transport
  def initialize(transport : CyberonMCP::Transport)
    @transport = transport
    @client = CyberonMCP::Client.new(transport)
    @client.init_connection
  end

  # Process an  format tool call
  def process_tool_call(tool_call_json : String) : String
    ToolProcessor.process_tool_call(tool_call_json, @client)
  end

  # Create a convenience method to close everything gracefully
  def shutdown
    begin
      # Try to exit cleanly
      @client.exit
    rescue ex : Exception
      # If exit fails, just close the transport directly
      @transport.close
    end
  end

  # Add to cyberon_llm_integration.cr

  def extract_tool_calls(llm_response : String) : Array(JSON::Any)
    tool_calls = [] of JSON::Any

    # Try to parse the entire response as JSON first
    begin
      parsed = JSON.parse(llm_response)
      if parsed["tool_calls"]?.try(&.as_a?)
        # This seems to be a properly formatted response with tool_calls array
        return parsed["tool_calls"].as_a
      end
    rescue
      # Not JSON or doesn't have tool_calls, continue with regex extraction
    end

    # More sophisticated regex for tool call extraction
    # This handles both JSON formatted and markdown code block formatted tool calls
    tool_call_patterns = [
      /```json\s*(\{\s*"function_call"\s*:.+?)\s*```/m,
      /"function_call"\s*:\s*\{[^}]*"name"\s*:\s*"[^"]*"[^}]*"arguments"\s*:\s*\{[^}]*\}\s*\}/m,
    ]

    tool_call_patterns.each do |pattern|
      llm_response.scan(pattern) do |match|
        begin
          # Try to parse the extracted JSON
          json_str = match[1]? || match[0]
          parsed = JSON.parse(json_str)

          # If it has function_call, it's a tool call
          if parsed["function_call"]?
            tool_calls << parsed
          end
        rescue ex : Exception
          # Skip invalid JSON
          next
        end
      end
    end

    return tool_calls
  end
end
