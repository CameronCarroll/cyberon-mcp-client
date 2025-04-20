require "./spec_helper"

# Integration tests for ProcessTransport with Client
describe "ProcessTransport with Client Integration" do
  server_path = MOCK_SERVER_SCRIPT

  it "successfully initializes and communicates with the server" do
    # Create the transport
    transport = CyberonMCP::ProcessTransport.new(server_path)
    transport.launch_server
    
    begin
      # Create the client with the transport
      client = CyberonMCP::Client.new(transport)
      
      # Initialize the connection
      server_info = client.init_connection
      
      # Verify the server info
      server_info.should be_a(Hash(String, JSON::Any))
      server_info["capabilities"]?.should_not be_nil
      
      # Verify the capabilities were stored
      client.server_capabilities["cyberon"]["search"].should eq(true)
      client.server_capabilities["cyberon"]["entity"].should eq(true)
      client.server_capabilities["resources"]["read"].should eq(true)
      client.server_capabilities["resources"]["list"].should eq(true)
      
      # Verify client is initialized
      client.initialized?.should eq(true)
      
      # Test sending another request
      response = client.send_request("test_request", {"param" => "value"})
      response["result"]?.should_not be_nil
      response["result"]["method"].should eq("test_request")
      response["result"]["echo"]["param"].should eq("value")
      
      # Test shutdown
      result = client.shutdown
      result.should eq(true)
      
    ensure
      # Clean up
      transport.close
    end
  end
  
  it "gracefully handles server exit and cleanup" do
    transport = CyberonMCP::ProcessTransport.new(server_path)
    transport.launch_server
    
    # Create the client
    client = CyberonMCP::Client.new(transport)
    
    # Initialize the connection
    client.init_connection
    
    # Verify the server is running
    transport.server_alive?.should eq(true)
    
    # Send exit notification
    client.exit
    
    # Verify the server has been terminated
    transport.server_alive?.should eq(false)
  end
end