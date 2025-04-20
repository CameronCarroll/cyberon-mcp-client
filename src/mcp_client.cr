# src/mcp_client.cr
require "json"
require "log"

require "./transport"
require "./errors"

# Namespace module
module CyberonMCP
  # Feature modules will be nested in here
  module Features
  end

  # Main MCP Client class for communicating with a CYBERON MCP server.
  class Client
    # The transport mechanism used for communication.
    @transport : Transport? = nil

    # Information about this client, sent during initialization.
    @client_info : Hash(String, String) = {"name" => "Crystal MCP Client", "version" => "0.1.0"}

    # Capabilities reported by the server after successful initialization.
    @server_capabilities : Hash(String, JSON::Any) = {} of String => JSON::Any

    # Indicates if the client has successfully initialized with the server.
    @initialized : Bool = false

    # Next request ID counter
    @next_id : Int32 = 1

    # Logger instance for logging client activities.
    class_getter logger = Log.for("mcp_client")

    # Sets the global log level for all Client instances.
    def self.log_level=(level : Log::Severity)
      Log.builder.bind("mcp_client", level, Log::IOBackend.new)
    end

    # Creates a new Client instance.
    def initialize(transport : Transport? = nil, client_name : String = "Crystal MCP Client", client_version : String = "0.1.0")
      @transport = transport
      @client_info = {
        "name"    => client_name,
        "version" => client_version,
      }
      self.class.logger.info { "MCP client created. Transport #{transport ? "set" : "not set"}." }
    end

    # Define property getters
    def transport
      @transport
    end

    def client_info
      @client_info
    end

    def server_capabilities
      @server_capabilities
    end

    def initialized?
      @initialized
    end

    # Sets the transport for the client
    def set_transport(transport : Transport)
      @transport = transport
      self.class.logger.info { "Transport set to: #{transport.class.name}" }
    end

    # Initializes the connection with the MCP server
    def init_connection : Hash(String, JSON::Any)
      unless @transport
        raise MCPRuntimeError.new("No transport set for the client. Call set_transport first.")
      end
      if @initialized
        self.class.logger.warn { "Client already initialized. Re-initializing." }
        @initialized = false
      end

      params = {"client_info" => @client_info}
      response = send_request("initialize", params)

      if error = response["error"]?
        err_obj = error.as_h? || {"code" => -32603, "message" => "Invalid error format"}
        raise MCPValueError.new("Error initializing MCP connection: #{err_obj["message"]} (Code: #{err_obj["code"]})")
      end

      result = response["result"].as_h?
      unless result
        raise MCPValueError.new("Invalid initialization response: 'result' field is missing or not an object.")
      end

      # Server can use either "supports" (actual server) or "capabilities" (documentation)
      if supports = result["supports"]?.try(&.as_h?)
        @server_capabilities = supports
      elsif capabilities = result["capabilities"]?.try(&.as_h?)
        @server_capabilities = capabilities
      else
        @server_capabilities = {} of String => JSON::Any
        self.class.logger.warn { "Server did not return 'supports' or 'capabilities' field in initialization response" }
      end

      @initialized = true

      self.class.logger.info { "MCP client initialized successfully with server." }
      self.class.logger.debug { "Server capabilities: #{@server_capabilities.to_json}" }

      send_notification("initialized", {} of String => String)
      self.class.logger.debug { "Sent 'initialized' notification." }
      result
    end

    # Gets the server capabilities (could fetch or return cached)
    def get_capabilities : Hash(String, JSON::Any)
      ensure_initialized
      # For simplicity, returning cached. Could add a fetch logic if needed.
      @server_capabilities
    end

    # Sends a shutdown request
    # Note: Not all MCP servers implement this method
    def shutdown : Bool
      ensure_initialized
      response = send_request("shutdown", {} of String => String)
      if error = response["error"]?
        err_obj = error.as_h

        # Check if it's a "method not found" error
        if err_obj["code"]?.try(&.as_i?) == -32601
          self.class.logger.warn { "Shutdown method not supported by this server" }
          # Return true as we'll just skip this step
          return true
        else
          self.class.logger.error { "Shutdown request failed: #{err_obj["message"]} (Code: #{err_obj["code"]})" }
          return false
        end
      else
        self.class.logger.info { "Shutdown request acknowledged by server." }
        return true
      end
    end

    # Sends an exit notification and properly closes the transport
    def exit
      if @transport
        begin
          # Send exit notification first
          send_notification("exit", {} of String => String)
          self.class.logger.info { "Sent 'exit' notification." }

          # Close the transport
          @transport.not_nil!.close
          self.class.logger.info { "Transport closed." }
        rescue ex
          self.class.logger.warn { "Error during transport exit/close: #{ex.message}" }
        end
      else
        self.class.logger.warn { "Cannot send 'exit' notification, no transport available." }
      end
      @initialized = false
    end

    # Helper method for tests to reset the request ID counter
    def reset_next_id_for_tests
      @next_id = 1
    end

    # --- Helper Methods ---

    # Sends a request and returns the response hash
    def send_request(method : String, params) : Hash(String, JSON::Any)
      unless @transport
        raise MCPRuntimeError.new("No transport set for the client. Call set_transport first.")
      end

      transport = @transport.not_nil!
      request_id = @next_id
      @next_id += 1

      request = {jsonrpc: "2.0", id: request_id, method: method, params: params}
      request_json = request.to_json
      self.class.logger.debug { "Sending request (ID: #{request_id}): #{request_json}" }

      response_json = transport.send_and_receive(request_json)
      self.class.logger.debug { "Received response (ID: #{request_id}): #{response_json}" }

      begin
        response = JSON.parse(response_json)
        parsed_response = response.as_h?
        unless parsed_response
          self.class.logger.error { "Invalid JSON response type: Expected object, got #{response.class.name}. Response: #{response_json}" }
          return wrap_error(-32600, "Invalid response type: Expected JSON object")
        end
        # Optional: ID check
        response_id = parsed_response["id"]?
        if !parsed_response.has_key?("error") && response_id && response_id.raw != request_id
          self.class.logger.warn { "Received response with mismatched ID. Expected #{request_id}, got #{response_id.raw}" }
        end
        parsed_response
      rescue ex : JSON::ParseException
        self.class.logger.error { "Failed to parse JSON response: #{ex.message}. Response: #{response_json}" }
        wrap_error(-32700, "Parse error: Invalid JSON received")
      rescue ex : Exception
        self.class.logger.error { "Error processing response: #{ex.message}" }
        wrap_error(-32603, "Internal error processing response: #{ex.message}")
      end
    end

    # Sends a notification (fire-and-forget, mostly)
    private def send_notification(method : String, params)
      transport = @transport.not_nil!

      notification = {jsonrpc: "2.0", method: method, params: params}
      notification_json = notification.to_json
      self.class.logger.debug { "Sending notification: #{notification_json}" }

      # Handling notification send depends heavily on transport capabilities
      # StdioTransport will block waiting for a response here, which is incorrect for notifications.
      # A robust solution requires a Transport interface supporting send-only,
      # or specific handling per transport type.
      if transport.is_a?(StdioTransport)
        self.class.logger.warn { "Attempting notification via StdioTransport; may block inappropriately." }
      end
      begin
        # Call send_and_receive but ignore the response (best we can do with current Transport)
        transport.send_and_receive(notification_json)
      rescue ex : Exception
        self.class.logger.error { "Error trying to send notification via #{transport.class.name}: #{ex.message}" }
      end
    end

    # Ensures client is initialized
    private def ensure_initialized
      raise MCPRuntimeError.new("MCP client not initialized. Call the 'init_connection' method first.") unless @initialized
    end

    # Ensures server supports a feature
    private def ensure_feature(*feature_path : String)
      current_value = @server_capabilities
      # Convert tuple to array for dynamic slicing
      path_array = feature_path.to_a

      feature_path.each_with_index do |key, index|
        # Build current path string by joining elements up to current index
        current_path = path_array[0..index].join('.')

        # Check if current value is a JSON::Any hash before trying to access keys
        if current_value.is_a?(Hash(String, JSON::Any))
          sub_value = current_value[key]?
          if sub_value
            # If we found a value, continue checking
            if index == feature_path.size - 1
              # This is the final key in the path, check if it's a supported feature
              if sub_value.as_bool? == false
                raise MCPValueError.new("Server does not support feature: '#{current_path}' (explicitly disabled)")
              elsif sub_value.as_bool? || sub_value.as_h? || sub_value.as_a?
                return # Feature is supported (true, object or array)
              else
                raise MCPValueError.new("Server does not support feature: '#{current_path}' (invalid value: #{sub_value.raw})")
              end
            else
              # Not the final key, this should be a nested object
              if sub_hash = sub_value.as_h?
                current_value = sub_hash
              else
                raise MCPValueError.new("Server capability path '#{current_path}' is not a nested object, cannot check deeper.")
              end
            end
          else
            raise MCPValueError.new("Server does not support feature: '#{current_path}' (missing)")
          end
        else
          # Handle if current_value is a JSON::Any (non-hash), which shouldn't normally happen
          if index == 0
            raise MCPValueError.new("Server capabilities structure is invalid")
          else
            raise MCPValueError.new("Server capability path '#{path_array[0..index - 1].join('.')}' is not a valid object")
          end
        end
      end
    end

    # Helper to wrap errors in JSON-RPC structure
    private def wrap_error(code : Int32, message : String, data = nil) : Hash(String, JSON::Any)
      error_obj = {"code" => code, "message" => message}
      error_obj["data"] = data unless data.nil?
      # Ensure the error object itself is valid JSON::Any for the outer hash
      error_json = JSON.parse(error_obj.to_json)

      # Create a result with all values as JSON::Any
      result = {} of String => JSON::Any
      result["jsonrpc"] = JSON::Any.new("2.0")
      result["id"] = JSON::Any.new(nil)
      result["error"] = error_json

      result
    end
  end
end

# Load feature modules
require "./client/features/ontology"
require "./client/features/prompts"
require "./client/features/resources"
require "./client/features/tools"

# Include feature modules in Client class
module CyberonMCP
  class Client
    include Features::Ontology
    include Features::Prompts
    include Features::Resources
    include Features::Tools
  end
end
