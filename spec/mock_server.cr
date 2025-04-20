#!/usr/bin/env crystal
# spec/mock_server.cr
#
# A simple mock server that reads a JSON-RPC request from stdin
# and sends a predefined response to stdout.
# Used for testing the ProcessTransport class.

require "json"

# Loop forever, reading requests and sending responses
loop do
  request_json = gets
  break unless request_json

  begin
    request = JSON.parse(request_json)
    
    # Extract the ID and method to create a response
    id = request["id"]?
    method = request["method"]?
    
    response = if method == "initialize"
      # Return capabilities for initialize
      {
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => {
          "capabilities" => {
            "cyberon" => {
              "search" => true,
              "entity" => true
            },
            "resources" => {
              "read" => true,
              "list" => true
            }
          },
          "serverInfo" => {
            "name" => "MockServer",
            "version" => "1.0.0"
          }
        }
      }
    elsif method == "initialized"
      # Response for initialized notification
      {
        "jsonrpc" => "2.0", 
        "id" => nil, 
        "result" => nil
      }
    elsif method == "exit"
      # Exit notification doesn't need a response
      # But test transport expects one, so echo back an empty result
      result = {
        "jsonrpc" => "2.0",
        "id" => nil,
        "result" => nil
      }
      puts result.to_json
      STDOUT.flush
      
      STDERR.puts "Received exit request, exiting server"
      exit(0)
    elsif method == "server/capabilities"
      # Return capabilities
      {
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => {
          "cyberon" => {
            "search" => true,
            "entity" => true
          },
          "resources" => {
            "read" => true,
            "list" => true
          }
        }
      }
    elsif method == "shutdown"
      # Return null result for shutdown
      result = {
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => nil
      }
      puts result.to_json
      STDOUT.flush
      
      STDERR.puts "Received shutdown request, preparing to exit"
      # Don't exit, wait for exit notification
      next
    elsif method == "test_request" || method == "cyberon/search" || method == "cyberon/entity"
      # Echo back a result for any other method
      {
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => {
          "method" => method,
          "received" => true,
          "echo" => request["params"]?
        }
      }
    else
      # Default echo response for any other method
      {
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => {
          "method" => method,
          "received" => true,
          "echo" => request["params"]?
        }
      }
    end
    
    # Send the response
    puts response.to_json
    STDOUT.flush
    
  rescue ex
    # If there's a parse error, send an error response
    error_response = {
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => {
        "code" => -32700,
        "message" => "Parse error: #{ex.message}"
      }
    }
    puts error_response.to_json
    STDERR.puts "Error processing request: #{ex.message}"
  end
end

STDERR.puts "No more input, exiting"
exit(0)