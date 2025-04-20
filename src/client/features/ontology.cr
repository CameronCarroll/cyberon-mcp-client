# src/client/features/ontology.cr
require "json"
require "../../errors" # Adjust path relative to mcp_client.cr location

# Module containing ontology-related methods for CyberonMCP::Client
module CyberonMCP::Features::Ontology
  # Searches for entities in the ontology
  def search_entities(query : String, entity_types : Array(String)? = nil, limit : Int32 = 10) : Hash(String, JSON::Any)
    ensure_initialized
    ensure_feature("cyberon", "search")

    # Use a generic Hash that can hold different types
    params = {} of String => (String | Int32 | Array(String))
    params["query"] = query
    params["limit"] = limit
    params["entityTypes"] = entity_types if entity_types

    response = send_request("cyberon/search", params)

    if error = response["error"]?
      err_obj = error.as_h
      # Use logger from main class
      CyberonMCP::Client.logger.error { "Error searching entities for query '#{query}': #{err_obj["message"]} (Code: #{err_obj["code"]})" }
      # Convert to proper return type with proper JSON::Any values
      result = {} of String => JSON::Any
      result["entities"] = JSON::Any.new([] of JSON::Any)
      result["error"] = JSON::Any.new(err_obj)
      result["query"] = JSON::Any.new(query)
      return result
    end
    response["result"].as_h? || wrap_error(-32602, "Invalid result format for cyberon/search")
  end

  # Gets detailed information about an entity
  def get_entity(entity_id : String) : Hash(String, JSON::Any)
    ensure_initialized
    ensure_feature("cyberon", "entity")

    params = {"entityId" => entity_id}
    response = send_request("cyberon/entity", params)

    if error = response["error"]?
      err_obj = error.as_h
      CyberonMCP::Client.logger.error { "Error getting entity #{entity_id}: #{err_obj["message"]} (Code: #{err_obj["code"]})" }
      result = {} of String => JSON::Any
      result["error"] = JSON::Any.new(err_obj)
      return result
    end
    response["result"].as_h? || wrap_error(-32602, "Invalid result format for cyberon/entity")
  end

  # Finds paths between entities in the ontology
  def find_paths(source_id : String, target_id : String, max_length : Int32 = 3) : Hash(String, JSON::Any)
    ensure_initialized
    ensure_feature("cyberon", "paths")

    params = {} of String => (String | Int32)
    params["sourceId"] = source_id
    params["targetId"] = target_id
    params["maxLength"] = max_length
    response = send_request("cyberon/paths", params)

    if error = response["error"]?
      err_obj = error.as_h
      CyberonMCP::Client.logger.error { "Error finding paths between #{source_id} and #{target_id}: #{err_obj["message"]} (Code: #{err_obj["code"]})" }
      result = {} of String => JSON::Any
      result["paths"] = JSON::Any.new([] of JSON::Any)
      result["error"] = JSON::Any.new(err_obj)
      return result
    end
    response["result"].as_h? || wrap_error(-32602, "Invalid result format for cyberon/paths")
  end

  # Finds connected entities in the ontology
  def find_connections(entity_id : String, max_distance : Int32 = 2) : Hash(String, JSON::Any)
    ensure_initialized
    ensure_feature("cyberon", "connections")

    params = {} of String => (String | Int32)
    params["entityId"] = entity_id
    params["maxDistance"] = max_distance
    response = send_request("cyberon/connections", params)

    if error = response["error"]?
      err_obj = error.as_h
      CyberonMCP::Client.logger.error { "Error finding connections for #{entity_id}: #{err_obj["message"]} (Code: #{err_obj["code"]})" }
      result = {} of String => JSON::Any
      result["connections"] = JSON::Any.new([] of JSON::Any)
      result["error"] = JSON::Any.new(err_obj)
      return result
    end
    response["result"].as_h? || wrap_error(-32602, "Invalid result format for cyberon/connections")
  end

  # Gets all entity types in the ontology
  def get_entity_types : Hash(String, JSON::Any)
    ensure_initialized
    ensure_feature("cyberon", "entityTypes")

    response = send_request("cyberon/entityTypes", {} of String => String)

    if error = response["error"]?
      err_obj = error.as_h
      CyberonMCP::Client.logger.error { "Error getting entity types: #{err_obj["message"]} (Code: #{err_obj["code"]})" }
      result = {} of String => JSON::Any
      result["entityTypes"] = JSON::Any.new([] of JSON::Any)
      result["error"] = JSON::Any.new(err_obj)
      return result
    end
    response["result"].as_h? || wrap_error(-32602, "Invalid result format for cyberon/entityTypes")
  end

  # Gets all relationship types in the ontology
  def get_relationship_types : Hash(String, JSON::Any)
    ensure_initialized
    ensure_feature("cyberon", "relationshipTypes")

    response = send_request("cyberon/relationshipTypes", {} of String => String)

    if error = response["error"]?
      err_obj = error.as_h
      CyberonMCP::Client.logger.error { "Error getting relationship types: #{err_obj["message"]} (Code: #{err_obj["code"]})" }
      result = {} of String => JSON::Any
      result["relationshipTypes"] = JSON::Any.new([] of JSON::Any)
      result["error"] = JSON::Any.new(err_obj)
      return result
    end
    response["result"].as_h? || wrap_error(-32602, "Invalid result format for cyberon/relationshipTypes")
  end
end
