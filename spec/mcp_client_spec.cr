# spec/mcp_client_spec.cr
require "./spec_helper"
require "./mock_transport" # Our mock transport

# Helper to create standard JSON responses for tests
def json_ok_result(id, result_payload)
  {jsonrpc: "2.0", id: id, result: result_payload}.to_json
end

def json_error(id, code, message, data = nil)
  error_obj = {"code" => code, "message" => message}
  error_obj["data"] = data if data
  {jsonrpc: "2.0", id: id, error: error_obj}.to_json
end

# Test helper class
class ClientTester
  property transport : MockTransport
  property client : CyberonMCP::Client
  
  def initialize
    @transport = MockTransport.new
    @client = CyberonMCP::Client.new
    @client.set_transport(@transport)
  end
  
  def reset
    @transport.reset
    @client.reset_next_id_for_tests
  end
  
  def init_client_for_tests
    client_info = @client.client_info
    init_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
    
    # Create more detailed capabilities that match what methods expect
    caps = {
      "cyberon" => {
        "search" => true, 
        "entity" => true,
        "paths" => true,
        "connections" => true,
        "entityTypes" => true,
        "relationshipTypes" => true
      },
      "resources" => {
        "read" => true,
        "list" => true,
        "templates" => {
          "list" => true
        }
      },
      "prompts" => {
        "list" => true,
        "get" => true
      },
      "tools" => {
        "list" => true,
        "schema" => true,
        "execute" => true
      }
    }
    
    init_response = json_ok_result(1, {"capabilities" => caps})
    init_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
    init_notification_response = {jsonrpc: "2.0", id: nil, result: nil}.to_json

    @transport.expect(init_request, init_response)
    @transport.expect(init_notification, init_notification_response)
    @client.init_connection
    @client.reset_next_id_for_tests
  end
end

# --- Tests ---

describe CyberonMCP::Client do
  # Create a tester for each test
  tester = ClientTester.new

  # Reset before each test
  before_each { tester.reset }

  describe "#init_connection (protocol method)" do
    it "initializes successfully and stores capabilities" do
      # Arrange
      client_info = tester.client.client_info
      expected_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
      server_caps = {"featureA" => true, "cyberon" => {"search" => true}}
      mock_response = json_ok_result(1, {"capabilities" => server_caps, "serverInfo" => {"name" => "MockServer"}})
      expected_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json

      tester.transport.expect(expected_request, mock_response)
      # Expect the 'initialized' notification (it uses send_and_receive internally)
      # We need to give it *some* response, even if ignored. A nil response is simple.
      tester.transport.expect(expected_notification, {jsonrpc: "2.0", id: nil, result: nil}.to_json)

      # Act
      result = tester.client.init_connection

      # Assert
      tester.client.initialized?.should eq(true)
      tester.client.server_capabilities.should eq(JSON.parse(server_caps.to_json)) # Compare parsed JSON::Any
      result.should eq(JSON.parse({"capabilities" => server_caps, "serverInfo" => {"name" => "MockServer"}}.to_json))
      tester.transport.received?(expected_notification).should be_true
    end

    it "raises MCPValueError if server returns an error" do
      # Arrange
      client_info = tester.client.client_info
      expected_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
      mock_response = json_error(1, -32600, "Init failed")

      tester.transport.expect(expected_request, mock_response)

      # Act & Assert
      expect_raises(MCPValueError, /Error initializing MCP connection: Init failed/) do
        tester.client.init_connection
      end
      tester.client.initialized?.should eq(false)
    end

    it "raises MCPRuntimeError if no transport is set" do
      # Arrange
      client_no_transport = CyberonMCP::Client.new

      # Act & Assert
      expect_raises(MCPRuntimeError, /No transport set/) do
        client_no_transport.init_connection
      end
    end

    it "propagates transport errors during initialization" do
       # Arrange
       client_info = tester.client.client_info
       expected_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
       transport_error = IO::Error.new("Connection refused")

       tester.transport.expect(expected_request, transport_error)

       # Act & Assert
       expect_raises(IO::Error, /Connection refused/) do
         tester.client.init_connection
       end
       tester.client.initialized?.should eq(false)
    end
  end

  describe "methods requiring initialization" do
    before_each do
      # Initialize the client for this test block
      tester.init_client_for_tests
    end

    it "raises MCPRuntimeError if called before initialization" do
      # Arrange
      uninitialized_client = CyberonMCP::Client.new
      uninitialized_client.set_transport(tester.transport) # New client, not initialized

      # Act & Assert
      expect_raises(MCPRuntimeError, /MCP client not initialized/) do
        uninitialized_client.search_entities("test")
      end
      expect_raises(MCPRuntimeError, /MCP client not initialized/) do
        uninitialized_client.shutdown
      end
      # Add more methods as needed
    end

    describe "#search_entities" do
      it "sends request and returns successful result" do
        # Setup a fresh client with proper capabilities
        fresh_tester = ClientTester.new
        # Set capabilities
        client_info = fresh_tester.client.client_info
        init_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
        caps = {"cyberon" => {"search" => true, "entity" => true}}
        init_response = json_ok_result(1, {"capabilities" => caps})
        init_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
        init_notification_response = {jsonrpc: "2.0", id: nil, result: nil}.to_json

        # First setup init requests
        fresh_tester.transport.expect(init_request, init_response)
        fresh_tester.transport.expect(init_notification, init_notification_response)
        fresh_tester.client.init_connection
        fresh_tester.client.reset_next_id_for_tests

        # Now setup the actual test requests
        expected_request = {jsonrpc: "2.0", id: 1, method: "cyberon/search", params: {"query" => "test", "limit" => 10}}.to_json
        mock_response_payload = {"entities" => [{"id" => "e1", "name" => "Entity 1"}]}
        mock_response = json_ok_result(1, mock_response_payload)
        fresh_tester.transport.expect(expected_request, mock_response)

        # Act
        result = fresh_tester.client.search_entities("test")

        # Assert
        result.should eq(JSON.parse(mock_response_payload.to_json))
      end

      it "sends request with types/limit and returns result" do
        # Setup a fresh client with proper capabilities
        fresh_tester = ClientTester.new
        # Set capabilities
        client_info = fresh_tester.client.client_info
        init_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
        caps = {"cyberon" => {"search" => true, "entity" => true}}
        init_response = json_ok_result(1, {"capabilities" => caps})
        init_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
        init_notification_response = {jsonrpc: "2.0", id: nil, result: nil}.to_json

        # First setup init requests
        fresh_tester.transport.expect(init_request, init_response)
        fresh_tester.transport.expect(init_notification, init_notification_response)
        fresh_tester.client.init_connection
        fresh_tester.client.reset_next_id_for_tests

        # Now setup the actual test requests
        params = {"query" => "test", "limit" => 5, "entityTypes" => ["TypeA"]}
        expected_request = {jsonrpc: "2.0", id: 1, method: "cyberon/search", params: params}.to_json
        mock_response_payload = {"entities" => [] of Hash(String, JSON::Any)} # Empty result is fine
        mock_response = json_ok_result(1, mock_response_payload)
        fresh_tester.transport.expect(expected_request, mock_response)

        # Act
        result = fresh_tester.client.search_entities("test", entity_types: ["TypeA"], limit: 5)

        # Assert
        result.should eq(JSON.parse(mock_response_payload.to_json))
      end


      it "returns error structure if server responds with error" do
        # Setup a fresh client with proper capabilities
        fresh_tester = ClientTester.new
        # Set capabilities
        client_info = fresh_tester.client.client_info
        init_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
        caps = {"cyberon" => {"search" => true, "entity" => true}}
        init_response = json_ok_result(1, {"capabilities" => caps})
        init_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
        init_notification_response = {jsonrpc: "2.0", id: nil, result: nil}.to_json

        # First setup init requests
        fresh_tester.transport.expect(init_request, init_response)
        fresh_tester.transport.expect(init_notification, init_notification_response)
        fresh_tester.client.init_connection
        fresh_tester.client.reset_next_id_for_tests

        # Now setup the actual test requests
        expected_request = {jsonrpc: "2.0", id: 1, method: "cyberon/search", params: {"query" => "fail", "limit" => 10}}.to_json
        mock_response = json_error(1, -32001, "Search failed")
        fresh_tester.transport.expect(expected_request, mock_response)

        # Act
        result = fresh_tester.client.search_entities("fail")

        # Assert
        error = result["error"]?
        error.should_not be_nil
        if error
          error["message"]?.should eq("Search failed")
        end
        result["entities"]?.should_not be_nil # Check for the added 'entities' key on error
      end
    end

    describe "#get_entity" do
        it "sends request and returns entity data" do
          # Setup a fresh client with proper capabilities
          fresh_tester = ClientTester.new
          # Set capabilities
          client_info = fresh_tester.client.client_info
          init_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
          caps = {"cyberon" => {"search" => true, "entity" => true}}
          init_response = json_ok_result(1, {"capabilities" => caps})
          init_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
          init_notification_response = {jsonrpc: "2.0", id: nil, result: nil}.to_json

          # First setup init requests
          fresh_tester.transport.expect(init_request, init_response)
          fresh_tester.transport.expect(init_notification, init_notification_response)
          fresh_tester.client.init_connection
          fresh_tester.client.reset_next_id_for_tests

          # Now setup the actual test requests
          expected_request = {jsonrpc: "2.0", id: 1, method: "cyberon/entity", params: {"entityId" => "ent123"}}.to_json
          mock_response_payload = {"id" => "ent123", "type" => "Person", "properties" => {"name" => "Alice"}}
          mock_response = json_ok_result(1, mock_response_payload)
          fresh_tester.transport.expect(expected_request, mock_response)

          # Act
          result = fresh_tester.client.get_entity("ent123")

          # Assert
          result.should eq(JSON.parse(mock_response_payload.to_json))
        end

        it "returns error structure on server error" do
          # Setup a fresh client with proper capabilities
          fresh_tester = ClientTester.new
          # Set capabilities
          client_info = fresh_tester.client.client_info
          init_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
          caps = {"cyberon" => {"search" => true, "entity" => true}}
          init_response = json_ok_result(1, {"capabilities" => caps})
          init_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
          init_notification_response = {jsonrpc: "2.0", id: nil, result: nil}.to_json

          # First setup init requests
          fresh_tester.transport.expect(init_request, init_response)
          fresh_tester.transport.expect(init_notification, init_notification_response)
          fresh_tester.client.init_connection
          fresh_tester.client.reset_next_id_for_tests

          # Now setup the actual test requests
          expected_request = {jsonrpc: "2.0", id: 1, method: "cyberon/entity", params: {"entityId" => "not_found"}}.to_json
          mock_response = json_error(1, -32002, "Entity not found")
          fresh_tester.transport.expect(expected_request, mock_response)

          # Act
          result = fresh_tester.client.get_entity("not_found")

          # Assert
          error = result["error"]?
          error.should_not be_nil
          if error
            error["message"]?.should eq("Entity not found")
          end
          result.has_key?("id").should be_false # Should only contain error
        end
    end

    # Add similar tests for other feature methods (find_paths, list_resources, execute_tool etc.)
    # Focus on: successful call, server error response, maybe invalid params (if client validates)

    describe "feature support" do
       it "raises MCPValueError if required feature is missing" do
          # First reinitialize with limited capabilities
          new_tester = ClientTester.new
          client_info = new_tester.client.client_info
          init_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
          
          # Create capabilities without tools
          caps = {
            "cyberon" => { "search" => true }
          }
          
          init_response = json_ok_result(1, {"capabilities" => caps})
          init_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
          init_notification_response = {jsonrpc: "2.0", id: nil, result: nil}.to_json
  
          new_tester.transport.expect(init_request, init_response)
          new_tester.transport.expect(init_notification, init_notification_response)
          new_tester.client.init_connection
          
          # Now test with this limited client
          expect_raises(MCPValueError, /Server does not support feature: 'tools'/) do
             new_tester.client.list_tools # Requires "tools" feature
          end
       end

       it "raises MCPValueError if nested feature is missing" do
         # First reinitialize with limited capabilities
         new_tester = ClientTester.new
         client_info = new_tester.client.client_info
         init_request = {jsonrpc: "2.0", id: 1, method: "initialize", params: {"clientInfo" => client_info}}.to_json
         
         # Create capabilities with missing list
         caps = {
           "resources" => {
             "read" => true
           }
         }
         
         init_response = json_ok_result(1, {"capabilities" => caps})
         init_notification = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
         init_notification_response = {jsonrpc: "2.0", id: nil, result: nil}.to_json
 
         new_tester.transport.expect(init_request, init_response)
         new_tester.transport.expect(init_notification, init_notification_response)
         new_tester.client.init_connection
         
         # Now test with this limited client
         expect_raises(MCPValueError, /Server does not support feature: 'resources.list'/) do
           new_tester.client.list_resources
         end
       end
    end


    describe "#shutdown" do
      it "sends shutdown request and returns true on success" do
        # Arrange
        expected_request = {jsonrpc: "2.0", id: 1, method: "shutdown", params: {} of String => String}.to_json
        # LSP spec says result is null for shutdown
        mock_response = {jsonrpc: "2.0", id: 1, result: nil}.to_json
        tester.transport.expect(expected_request, mock_response)

        # Act
        result = tester.client.shutdown

        # Assert
        result.should be_true
      end

      it "returns false on server error" do
        # Arrange
        expected_request = {jsonrpc: "2.0", id: 1, method: "shutdown", params: {} of String => String}.to_json
        mock_response = json_error(1, -32003, "Cannot shutdown now")
        tester.transport.expect(expected_request, mock_response)

        # Act
        result = tester.client.shutdown

        # Assert
        result.should be_false
      end
    end

    describe "#exit" do
      it "sends exit notification and sets initialized to false" do
        # Arrange
        expected_notification = {jsonrpc: "2.0", method: "exit", params: {} of String => String}.to_json
        # Expect the notification send, provide a dummy response for send_and_receive
        tester.transport.expect(expected_notification, {jsonrpc: "2.0", id: nil, result: nil}.to_json)

        # Pre-check
        tester.client.initialized?.should eq(true)

        # Act
        tester.client.exit

        # Assert
        tester.transport.received?(expected_notification).should be_true
        tester.client.initialized?.should eq(false)
      end
    end

  end # describe methods requiring initialization
end