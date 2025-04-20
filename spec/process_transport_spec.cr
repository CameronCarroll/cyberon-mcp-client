require "./spec_helper"

describe CyberonMCP::ProcessTransport do
  server_path = MOCK_SERVER_SCRIPT

  describe "#initialize" do
    it "creates a ProcessTransport with a valid server path" do
      transport = CyberonMCP::ProcessTransport.new(server_path)
      transport.should_not be_nil
    end

    it "raises an exception with an invalid server path" do
      expect_raises(IO::Error, /Server script not found/) do
        CyberonMCP::ProcessTransport.new("/nonexistent/path/to/server")
      end
    end
  end

  describe "#launch_server" do
    it "successfully launches the server process" do
      transport = CyberonMCP::ProcessTransport.new(server_path)
      result = transport.launch_server
      
      begin
        result.should eq(true)
        transport.server_alive?.should eq(true)
      ensure
        transport.close
      end
    end
    
    it "returns false when attempting to launch an already running server" do
      transport = CyberonMCP::ProcessTransport.new(server_path)
      transport.launch_server
      
      begin
        # Try to launch again
        result = transport.launch_server
        result.should eq(false)
      ensure
        transport.close
      end
    end
  end

  describe "#send_and_receive" do
    it "successfully sends a request and receives a response" do
      transport = CyberonMCP::ProcessTransport.new(server_path)
      transport.launch_server
      
      begin
        # Send a request
        request = {jsonrpc: "2.0", id: 1, method: "test", params: {"param1" => "value1"}}.to_json
        response = transport.send_and_receive(request)
        
        # Parse the response
        response_obj = JSON.parse(response)
        response_obj["jsonrpc"].should eq("2.0")
        response_obj["id"].should eq(1)
        response_obj["result"]?.should_not be_nil
        
        # Check that the response contains the expected values
        result = response_obj["result"]
        result["method"].should eq("test")
        result["received"].should eq(true)
        result["echo"]["param1"].should eq("value1")
      ensure
        transport.close
      end
    end
    
    it "raises an exception when used before launching the server" do
      transport = CyberonMCP::ProcessTransport.new(server_path)
      
      expect_raises(IO::Error, /Process transport not initialized/) do
        request = {jsonrpc: "2.0", id: 1, method: "test", params: {} of String => String}.to_json
        transport.send_and_receive(request)
      end
    end
  end

  describe "#close" do
    it "terminates the server process gracefully" do
      transport = CyberonMCP::ProcessTransport.new(server_path)
      transport.launch_server
      
      # Ensure the server is running
      transport.server_alive?.should eq(true)
      
      # Close the transport
      transport.close
      
      # Ensure the server is no longer running
      transport.server_alive?.should eq(false)
    end
    
    it "handles closing a transport that hasn't launched a server" do
      transport = CyberonMCP::ProcessTransport.new(server_path)
      
      # This should not raise an exception
      expect_not_raises do
        transport.close
      end
    end
  end
end