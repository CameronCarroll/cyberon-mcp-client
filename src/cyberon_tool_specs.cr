# src/cyberon_tool_specs.cr
require "json"

module CyberonToolSpecs
  # Tool specifications in OpenAI format
  TOOL_DEFINITIONS = [
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_search",
        "description": "Search for entities in the cybernetics ontology",
        "parameters":  {
          "type":       "object",
          "properties": {
            "query": {
              "type":        "string",
              "description": "The search query",
            },
            "entity_types": {
              "type":        "array",
              "items":       {"type": "string"},
              "description": "Optional filter by entity types",
            },
            "limit": {
              "type":        "integer",
              "description": "Maximum number of results to return",
              "default":     10,
            },
          },
          "required": ["query"],
        },
      },
    },
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_entity_info",
        "description": "Get detailed information about a specific entity",
        "parameters":  {
          "type":       "object",
          "properties": {
            "entity_id": {
              "type":        "string",
              "description": "The ID of the entity to retrieve",
            },
          },
          "required": ["entity_id"],
        },
      },
    },
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_find_paths",
        "description": "Find paths between entities in the ontology",
        "parameters":  {
          "type":       "object",
          "properties": {
            "source_id": {
              "type":        "string",
              "description": "Source entity ID",
            },
            "target_id": {
              "type":        "string",
              "description": "Target entity ID",
            },
            "max_length": {
              "type":        "integer",
              "description": "Maximum path length",
              "default":     3,
            },
          },
          "required": ["source_id", "target_id"],
        },
      },
    },
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_find_connections",
        "description": "Find entities connected to a specific entity",
        "parameters":  {
          "type":       "object",
          "properties": {
            "entity_id": {
              "type":        "string",
              "description": "Entity ID to find connections for",
            },
            "max_distance": {
              "type":        "integer",
              "description": "Maximum distance to search",
              "default":     2,
            },
          },
          "required": ["entity_id"],
        },
      },
    },
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_entity_types",
        "description": "Get all entity types in the ontology",
        "parameters":  {
          "type":       "object",
          "properties": {} of String => String,
        },
      },
    },
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_relationship_types",
        "description": "Get all relationship types in the ontology",
        "parameters":  {
          "type":       "object",
          "properties": {} of String => String,
        },
      },
    },
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_list_tools",
        "description": "List available tools for the cybernetics ontology",
        "parameters":  {
          "type":       "object",
          "properties": {} of String => String,
        },
      },
    },
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_execute_tool",
        "description": "Execute a specific tool with parameters",
        "parameters":  {
          "type":       "object",
          "properties": {
            "name": {
              "type":        "string",
              "description": "The name of the tool to execute",
            },
            "params": {
              "type":        "object",
              "description": "Parameters for the tool",
            },
          },
          "required": ["name", "params"],
        },
      },
    },
    {
      "type":     "function",
      "function": {
        "name":        "cyberon_list_resources",
        "description": "List available resources in the ontology",
        "parameters":  {
          "type":       "object",
          "properties": {} of String => String,
        },
      },
    },
  ]

  # Get tool definitions as JSON string
  def self.tool_definitions_json : String
    TOOL_DEFINITIONS.to_json
  end
end
