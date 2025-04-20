#!/usr/bin/env python3
# spec/mock_server.cr
#
# A simple mock server that reads a JSON-RPC request from stdin
# and sends a predefined response to stdout.
# Used for testing the ProcessTransport class.

import json
import sys

# Loop forever, reading requests and sending responses
while True:
    try:
        request_json = sys.stdin.readline().strip()
        if not request_json:
            break
            
        request = json.loads(request_json)
        
        # Extract the ID and method to create a response
        id = request.get("id")
        method = request.get("method")
        
        if method == "initialize":
            # Return capabilities for initialize
            response = {
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "capabilities": {
                        "cyberon": {
                            "search": True,
                            "entity": True,
                        },
                        "resources": {
                            "read": True,
                            "list": True,
                        },
                    },
                    "serverInfo": {
                        "name": "MockServer",
                        "version": "1.0.0",
                    },
                },
            }
        elif method == "initialized":
            # Response for initialized notification
            response = {
                "jsonrpc": "2.0",
                "id": None,
                "result": None,
            }
        elif method == "exit":
            # Exit notification doesn't need a response
            # But test transport expects one, so echo back an empty result
            result = {
                "jsonrpc": "2.0",
                "id": None,
                "result": None,
            }
            print(json.dumps(result))
            sys.stdout.flush()
            
            print("Received exit request, exiting server", file=sys.stderr)
            sys.exit(0)
        elif method == "server/capabilities":
            # Return capabilities
            response = {
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "cyberon": {
                        "search": True,
                        "entity": True,
                    },
                    "resources": {
                        "read": True,
                        "list": True,
                    },
                },
            }
        elif method == "shutdown":
            # Return null result for shutdown
            response = {
                "jsonrpc": "2.0",
                "id": id,
                "result": None,
            }
            print(json.dumps(response))
            sys.stdout.flush()
            
            print("Received shutdown request, preparing to exit", file=sys.stderr)
            continue
        elif method == "test_request" or method == "cyberon/search" or method == "cyberon/entity":
            # Echo back a result for specific methods
            response = {
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "method": method,
                    "received": True,
                    "echo": request.get("params"),
                },
            }
        else:
            # Default echo response for any other method
            response = {
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "method": method,
                    "received": True,
                    "echo": request.get("params"),
                },
            }
        
        # Send the response
        print(json.dumps(response))
        sys.stdout.flush()
        
    except Exception as ex:
        # If there's a parse error, send an error response
        error_response = {
            "jsonrpc": "2.0",
            "id": None,
            "error": {
                "code": -32700,
                "message": f"Parse error: {str(ex)}",
            },
        }
        print(json.dumps(error_response))
        print(f"Error processing request: {str(ex)}", file=sys.stderr)

print("No more input, exiting", file=sys.stderr)
sys.exit(0)
