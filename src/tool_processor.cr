# src/tool_processor.cr
require "json"
require "./cyberon_mcp_client" # Assuming this path is correct

module CyberonMCP
  module ToolProcessor
    # Define a type alias for clarity, accommodating nested parameters for execute_tool
    alias ToolCall = Hash(String, String | Hash(String, JSON::Any))
    alias ToolParameters = Hash(String, String | Hash(String, JSON::Any)) # Parameters might be simple strings or nested for execute_tool

    # Process a pre-parsed tool call hash and return the result as a JSON string
    def self.process_tool_call(tool_call : ToolCall, client : CyberonMCP::Client) : String
      begin
        # Extract function name and parameters from the hash
        # Use .as() for required fields assumed present by ToolCall type def
        tool_name = tool_call["function_name"].as(String)
        # Parameters could be simple String->String or nested for execute_tool
        # Default to empty hash if parameters are missing (though ToolCall implies it exists)
        arguments = tool_call["parameters"]?.as(ToolParameters) || ToolParameters.new

        # Process using appropriate method based on tool_name
        result = case tool_name
                when "cyberon_search"
                  process_search_call(arguments, client)
                when "cyberon_entity_info"
                  process_entity_call(arguments, client)
                when "cyberon_find_paths"
                  process_paths_call(arguments, client)
                when "cyberon_find_connections"
                  process_connections_call(arguments, client)
                when "cyberon_entity_types"
                  process_entity_types_call(client) # No arguments needed
                when "cyberon_relationship_types"
                  process_relationship_types_call(client) # No arguments needed
                when "cyberon_list_tools"
                  process_list_tools_call(client) # No arguments needed
                when "cyberon_execute_tool"
                  process_execute_tool_call(arguments, client)
                when "cyberon_list_resources"
                  process_list_resources_call(client) # No arguments needed
                else
                  {"error" => "Unknown tool: #{tool_name}"}.to_json
                end

        return result
      rescue key_error : KeyError
        # This might occur if 'function_name' is missing
        return {"error" => "Failed to process tool call: Missing key '#{key_error.key}'", "tool_call" => tool_call.to_json}.to_json
      rescue type_cast_error : TypeCastError
        # This might occur if 'function_name' or 'parameters' have wrong types
        return {"error" => "Failed to process tool call: Invalid type for key - #{type_cast_error.message}", "tool_call" => tool_call.to_json}.to_json
      rescue ex : Exception
        # General fallback exception handler
        return {"error" => "Failed to process tool call: #{ex.class_name} - #{ex.message}", "tool_call" => tool_call.to_json}.to_json
      end
    end

    # ==================================
    # Private Helper Methods
    # ==================================

    # Process entity search tool call
    # Assumes 'entity_types' is a comma-separated string if present
    private def self.process_search_call(arguments : ToolParameters, client : CyberonMCP::Client) : String
      # Use dig for safe access, then check type and handle nil
      query_val = arguments.dig?("query")
      unless query_val.is_a?(String)
        return {"error" => "Missing or invalid required parameter 'query' (String) for cyberon_search"}.to_json
      end
      query = query_val.as(String) # Safe cast after check

      # Handle optional 'limit' (Int)
      limit_val = arguments.dig?("limit")
      limit = if limit_val.is_a?(String)
                limit_val.to_i? || 10 # Try parsing string, default 10 if invalid/nil
              elsif limit_val.is_a?(Int)
                limit_val # Allow integer directly
              else
                10 # Default if missing or wrong type
              end

      # Handle optional 'entity_types' (String, comma-separated)
      entity_types_str = arguments.dig?("entity_types").as?(String) # Use as? for combined nil/type check

      params = {} of String => JSON::Any
      params["query"] = JSON::Any.new(query)
      params["limit"] = JSON::Any.new(limit)

      if entity_types_str && !entity_types_str.empty?
        entity_types_list = entity_types_str.split(',').map(&.strip).reject(&.empty?)
        unless entity_types_list.empty?
          entity_types_array = JSON::Any.new(entity_types_list.map { |t| JSON::Any.new(t) })
          params["entity_types"] = entity_types_array
        end
      end

      response = client.send_request("cyberon/search", params)
      response.to_json
    end

    # Process entity info tool call
    private def self.process_entity_call(arguments : ToolParameters, client : CyberonMCP::Client) : String
      entity_id_val = arguments.dig?("entity_id")
      unless entity_id_val.is_a?(String)
        return {"error" => "Missing or invalid required parameter 'entity_id' (String) for cyberon_entity_info"}.to_json
      end
      entity_id = entity_id_val.as(String)

      params = {} of String => JSON::Any
      params["entity_id"] = JSON::Any.new(entity_id)

      response = client.send_request("cyberon/entity", params)
      response.to_json
    end

    # Process find paths tool call
    private def self.process_paths_call(arguments : ToolParameters, client : CyberonMCP::Client) : String
      source_id_val = arguments.dig?("source_id")
      unless source_id_val.is_a?(String)
        return {"error" => "Missing or invalid required parameter 'source_id' (String) for cyberon_find_paths"}.to_json
      end
      source_id = source_id_val.as(String)

      target_id_val = arguments.dig?("target_id")
      unless target_id_val.is_a?(String)
        return {"error" => "Missing or invalid required parameter 'target_id' (String) for cyberon_find_paths"}.to_json
      end
      target_id = target_id_val.as(String)

      # Handle optional 'max_length' (Int)
      max_length_val = arguments.dig?("max_length")
      max_length = if max_length_val.is_a?(String)
                    max_length_val.to_i? || 3
                  elsif max_length_val.is_a?(Int)
                    max_length_val
                  else
                    3
                  end

      params = {} of String => JSON::Any
      params["source_id"] = JSON::Any.new(source_id)
      params["target_id"] = JSON::Any.new(target_id)
      params["max_length"] = JSON::Any.new(max_length)

      response = client.send_request("cyberon/paths", params)
      response.to_json
    end

    # Process find connections tool call
    private def self.process_connections_call(arguments : ToolParameters, client : CyberonMCP::Client) : String
      entity_id_val = arguments.dig?("entity_id")
      unless entity_id_val.is_a?(String)
        return {"error" => "Missing or invalid required parameter 'entity_id' (String) for cyberon_find_connections"}.to_json
      end
      entity_id = entity_id_val.as(String)

      # Handle optional 'max_distance' (Int)
      max_distance_val = arguments.dig?("max_distance")
      max_distance = if max_distance_val.is_a?(String)
                      max_distance_val.to_i? || 2
                    elsif max_distance_val.is_a?(Int)
                      max_distance_val
                    else
                      2
                    end

      params = {} of String => JSON::Any
      params["entity_id"] = JSON::Any.new(entity_id)
      params["max_distance"] = JSON::Any.new(max_distance)

      response = client.send_request("cyberon/connections", params)
      response.to_json
    end

    # Process entity types tool call (no arguments needed from input hash)
    private def self.process_entity_types_call(client : CyberonMCP::Client) : String
      params = {} of String => JSON::Any # Empty params
      response = client.send_request("cyberon/entity_types", params)
      response.to_json
    end

    # Process relationship types tool call (no arguments needed from input hash)
    private def self.process_relationship_types_call(client : CyberonMCP::Client) : String
      params = {} of String => JSON::Any # Empty params
      response = client.send_request("cyberon/relationship_types", params)
      response.to_json
    end

    # Process list tools tool call (no arguments needed from input hash)
    private def self.process_list_tools_call(client : CyberonMCP::Client) : String
      params = {} of String => JSON::Any # Empty params
      response = client.send_request("tools/list", params)
      response.to_json
    end

    # Process execute tool tool call
    # Assumes 'params' within arguments is a Hash
    private def self.process_execute_tool_call(arguments : ToolParameters, client : CyberonMCP::Client) : String
      tool_name_val = arguments.dig?("name")
      unless tool_name_val.is_a?(String)
        return {"error" => "Missing or invalid required parameter 'name' (String) for cyberon_execute_tool"}.to_json
      end
      tool_name = tool_name_val.as(String)

      # Handle optional 'params' (Hash)
      # Use as? for combined nil/type check
      tool_params_hash = arguments.dig?("params").as?(Hash(String, JSON::Any)) || {} of String => JSON::Any

      params = {} of String => JSON::Any
      params["name"] = JSON::Any.new(tool_name)
      # tool_params_hash is already Hash(String, JSON::Any) or an empty hash
      params["params"] = JSON::Any.new(tool_params_hash)

      response = client.send_request("tools/execute", params)
      response.to_json
    end

    # Process list resources tool call (no arguments needed from input hash)
    private def self.process_list_resources_call(client : CyberonMCP::Client) : String
      params = {} of String => JSON::Any # Empty params
      response = client.send_request("resources/list", params)
      response.to_json
    end
  end
end
