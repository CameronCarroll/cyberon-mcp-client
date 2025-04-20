# src/tool_processor.cr
require "json"
require "./mcp_client" # For CyberonMCP client integration

module ToolProcessor
  # Process a tool call in  format and return the result
  def self.process_tool_call(tool_call_json : String, client : CyberonMCP::Client) : String
    begin
      # Parse the  format
      parsed = JSON.parse(tool_call_json)

      # Extract function call details
      function_call = parsed["function_call"]
      tool_name = function_call["name"].as_s

      # Arguments could be a String or already parsed JSON
      arguments = if function_call["arguments"].as_s?
                    JSON.parse(function_call["arguments"].as_s)
                  else
                    function_call["arguments"]
                  end

      # Process using appropriate method
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
                 process_entity_types_call(client)
               when "cyberon_relationship_types"
                 process_relationship_types_call(client)
               when "cyberon_list_tools"
                 process_list_tools_call(client)
               when "cyberon_execute_tool"
                 process_execute_tool_call(arguments, client)
               when "cyberon_list_resources"
                 process_list_resources_call(client)
               else
                 {"error" => "Unknown tool: #{tool_name}"}.to_json
               end

      return result
    rescue ex : Exception
      return {"error" => "Failed to process tool call: #{ex.message}", "raw_input" => tool_call_json}.to_json
    end
  end

  # Process entity search tool call
  private def self.process_search_call(arguments : JSON::Any, client : CyberonMCP::Client) : String
    query = arguments["query"].as_s
    entity_types = arguments["entity_types"]?.try(&.as_a?)
    limit = arguments["limit"]?.try(&.as_i?) || 10

    params = {} of String => JSON::Any
    params["query"] = JSON::Any.new(query)
    params["limit"] = JSON::Any.new(limit)

    if entity_types
      entity_types_array = JSON::Any.new(entity_types.map { |t| JSON::Any.new(t.as_s) })
      params["entity_types"] = entity_types_array
    end

    response = client.send_request("cyberon/search", params)
    response.to_json
  end

  # Process entity info tool call
  private def self.process_entity_call(arguments : JSON::Any, client : CyberonMCP::Client) : String
    entity_id = arguments["entity_id"].as_s

    params = {} of String => JSON::Any
    params["entity_id"] = JSON::Any.new(entity_id)

    response = client.send_request("cyberon/entity", params)
    response.to_json
  end

  # Process find paths tool call
  private def self.process_paths_call(arguments : JSON::Any, client : CyberonMCP::Client) : String
    source_id = arguments["source_id"].as_s
    target_id = arguments["target_id"].as_s
    max_length = arguments["max_length"]?.try(&.as_i?) || 3

    params = {} of String => JSON::Any
    params["source_id"] = JSON::Any.new(source_id)
    params["target_id"] = JSON::Any.new(target_id)
    params["max_length"] = JSON::Any.new(max_length)

    response = client.send_request("cyberon/paths", params)
    response.to_json
  end

  # Process find connections tool call
  private def self.process_connections_call(arguments : JSON::Any, client : CyberonMCP::Client) : String
    entity_id = arguments["entity_id"].as_s
    max_distance = arguments["max_distance"]?.try(&.as_i?) || 2

    params = {} of String => JSON::Any
    params["entity_id"] = JSON::Any.new(entity_id)
    params["max_distance"] = JSON::Any.new(max_distance)

    response = client.send_request("cyberon/connections", params)
    response.to_json
  end

  # Process entity types tool call
  private def self.process_entity_types_call(client : CyberonMCP::Client) : String
    params = {} of String => JSON::Any
    response = client.send_request("cyberon/entity_types", params)
    response.to_json
  end

  # Process relationship types tool call
  private def self.process_relationship_types_call(client : CyberonMCP::Client) : String
    params = {} of String => JSON::Any
    response = client.send_request("cyberon/relationship_types", params)
    response.to_json
  end

  # Process list tools tool call
  private def self.process_list_tools_call(client : CyberonMCP::Client) : String
    params = {} of String => JSON::Any
    response = client.send_request("tools/list", params)
    response.to_json
  end

  # Process execute tool tool call
  private def self.process_execute_tool_call(arguments : JSON::Any, client : CyberonMCP::Client) : String
    tool_name = arguments["name"].as_s
    tool_params = arguments["params"]

    params = {} of String => JSON::Any
    params["name"] = JSON::Any.new(tool_name)
    params["params"] = tool_params

    response = client.send_request("tools/execute", params)
    response.to_json
  end

  # Process list resources tool call
  private def self.process_list_resources_call(client : CyberonMCP::Client) : String
    params = {} of String => JSON::Any
    response = client.send_request("resources/list", params)
    response.to_json
  end
end
