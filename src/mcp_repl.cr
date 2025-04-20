#!/usr/bin/env crystal
# src/mcp_repl.cr
# An interactive REPL for MCP Server that allows sending arbitrary JSON-RPC commands

require "./mcp_client"
require "./transport"
require "./errors"
require "log"
require "option_parser"
require "json"

# Configuration
SERVER_PATH = "./mcp_server.py" # Default path, run from main dir
LOG_LEVEL   = Log::Severity::Info

# Parse command line options
server_path = SERVER_PATH
log_level = LOG_LEVEL
use_shell = false

OptionParser.parse do |parser|
  parser.banner = "Usage: mcp_repl [options]"

  parser.on("-s PATH", "--server=PATH", "Path to MCP server script") do |path|
    server_path = path
  end

  parser.on("-v", "--verbose", "Enable verbose logging") do
    log_level = Log::Severity::Debug
  end

  parser.on("-S", "--shell", "Run server in shell") do
    use_shell = true
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end

# Configure logging
Log.setup do |config|
  backend = Log::IOBackend.new
  config.bind("*", log_level, backend)
end

# --- Color constants for output formatting ---
COLOR_RESET   = "\033[0m"
COLOR_RED     = "\033[91m"
COLOR_GREEN   = "\033[92m"
COLOR_YELLOW  = "\033[93m"
COLOR_BLUE    = "\033[94m"
COLOR_CYAN    = "\033[96m"
COLOR_MAGENTA = "\033[95m"
COLOR_BOLD    = "\033[1m"

def print_color(text, color = COLOR_RESET, bold = false)
  prefix = bold ? COLOR_BOLD : ""
  puts "#{prefix}#{color}#{text}#{COLOR_RESET}"
end

def print_divider(char = "*", length = 70, color = COLOR_CYAN)
  line = char * length
  print_color(line, color)
end

def display_help
  print_color("REPL Commands:", COLOR_CYAN, true)
  print_color("  help - Display this help", COLOR_CYAN)
  print_color("  exit - Exit the REPL", COLOR_CYAN)
  print_color("  init - Send initialize request", COLOR_CYAN)
  print_color("  caps - Send capabilities request", COLOR_CYAN)
  print_color("Examples (type or paste JSON directly):", COLOR_CYAN, true)
  print_color(%Q{  {"jsonrpc":"2.0","id":1,"method":"cyberon/search","params":{"query":"feedback"}}}, COLOR_CYAN)
  print_color("Advanced:", COLOR_CYAN, true)
  print_color("  1. View available methods:", COLOR_CYAN)
  print_color(%Q{     {"jsonrpc":"2.0","id":1,"method":"server/capabilities","params":{}}}, COLOR_CYAN)
  print_color("  2. Search entities:", COLOR_CYAN)
  print_color(%Q{     {"jsonrpc":"2.0","id":2,"method":"cyberon/search","params":{"query":"cybernetics","limit":3}}}, COLOR_CYAN)
  print_color("  3. List tools:", COLOR_CYAN)
  print_color(%Q{     {"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}}, COLOR_CYAN)
  print_color("  4. List resources:", COLOR_CYAN)
  print_color(%Q{     {"jsonrpc":"2.0","id":4,"method":"resources/list","params":{}}}, COLOR_CYAN)
  print_color("  5. Get entity info:", COLOR_CYAN)
  print_color(%Q{     {"jsonrpc":"2.0","id":5,"method":"cyberon/entity","params":{"entity_id":"cybernetics"}}}, COLOR_CYAN)
end

def build_request(command : String, request_id : Int32) : String?
  # Handle numeric-only input (user might be experimenting or typing numbers accidentally)
  if command.strip =~ /^\d+$/
    print_color("Numeric input detected. Please enter a valid command or JSON-RPC request.", COLOR_YELLOW)
    return nil
  end

  case command.strip.downcase
  when "init", "initialize"
    return {
      jsonrpc: "2.0",
      id:      request_id,
      method:  "initialize",
      params:  {
        client_info: {
          name:    "Crystal MCP REPL",
          version: "1.0.0",
        },
      },
    }.to_json
  when "caps", "capabilities"
    return {
      jsonrpc: "2.0",
      id:      request_id,
      method:  "server/capabilities",
      params:  {} of String => String,
    }.to_json
  else
    # Try to parse as JSON directly
    begin
      # Validate it's proper JSON-RPC
      parsed = JSON.parse(command)

      # Check if it has the required fields
      if parsed.as_h? && parsed["jsonrpc"]? && parsed["method"]? && parsed["id"]?
        return command # It's already valid JSON-RPC
      else
        print_color("Invalid JSON-RPC format. Must include jsonrpc, method, and id fields.", COLOR_YELLOW)
        return nil
      end
    rescue e : JSON::ParseException
      print_color("Invalid JSON: #{e.message}", COLOR_YELLOW)
      return nil
    end
  end
end

def pretty_print_json(json_str : String) : String
  begin
    parsed = JSON.parse(json_str)
    parsed.to_pretty_json
  rescue
    json_str # Return original if parsing fails
  end
end

# --- Main script ---
begin
  # Find the absolute path to the server
  server_abs_path = File.expand_path(server_path)

  # Check if the server script exists
  unless File.exists?(server_abs_path)
    print_color("ERROR: Server script not found at: #{server_abs_path}", COLOR_RED)
    print_color("Please provide a valid server path with the --server option.", COLOR_YELLOW)
    exit(1)
  end

  print_divider("=", 70, COLOR_BLUE)
  print_color("CRYSTAL MCP REPL CLIENT", COLOR_BLUE, true)
  print_divider("=", 70, COLOR_BLUE)
  print_color("Server path: #{server_abs_path}", COLOR_CYAN)

  # Create the transport and launch the server
  print_color("Creating transport and launching server...", COLOR_CYAN)
  transport = CyberonMCP::ProcessTransport.new(server_abs_path, use_shell)
  transport.launch_server
  print_color("Server process launched successfully!", COLOR_GREEN)

  # Create the client
  print_color("Creating MCP client...", COLOR_CYAN)
  client = CyberonMCP::Client.new(transport, "Crystal REPL Client", "1.0.0")

  # Show initial help
  print_divider("-", 70, COLOR_MAGENTA)
  display_help()
  print_divider("-", 70, COLOR_MAGENTA)

  # REPL loop
  request_id = 1
  initialized = false

  loop do
    print "\n#{COLOR_CYAN}mcp> #{COLOR_RESET}"
    command = gets

    # Exit if EOF (Ctrl+D) or nil
    break if command.nil?

    command = command.strip

    # Handle special commands
    case command.downcase
    when "exit", "quit"
      print_color("Exiting REPL...", COLOR_YELLOW)
      break
    when "help"
      display_help()
      next
    when "clear", "cls"
      print "\033[H\033[2J" # Clear screen
      next
    when ""
      next # Skip empty lines
    else
      # Build request JSON
      request_json = build_request(command, request_id)
      next if request_json.nil?

      request_id += 1 # Increment request ID for next command

      # Send the request
      print_color("\nSending request:", COLOR_GREEN)
      print_color(pretty_print_json(request_json), COLOR_GREEN)

      begin
        # Handle initialize command specially
        if command.downcase == "init" || command.downcase == "initialize"
          if initialized
            print_color("Client already initialized. Reinitializing...", COLOR_YELLOW)
          end

          # Use the built-in initialize method
          result = client.init_connection
          initialized = true

          print_color("\nResponse:", COLOR_MAGENTA)
          print_color(result.to_pretty_json, COLOR_MAGENTA)
        else
          # For JSON input, we need to check if we're initialized first
          unless initialized
            print_color("Client not initialized. Initializing first...", COLOR_YELLOW)
            client.init_connection
            initialized = true
          end

          # Parse to get method for direct request
          parsed_req = JSON.parse(request_json)
          method = parsed_req["method"].as_s

          # IMPORTANT: Don't convert params to JSON string, pass it directly
          # The send_request method will handle the conversion properly
          params = parsed_req["params"]

          # Use send_request with proper method and params
          response = client.send_request(method, params)

          print_color("\nResponse:", COLOR_MAGENTA)
          print_color(response.to_pretty_json, COLOR_MAGENTA)
        end
      rescue ex : MCPRuntimeError | MCPValueError
        print_color("MCP ERROR: #{ex.message}", COLOR_RED)
      rescue ex : Exception
        print_color("ERROR: #{ex.message}", COLOR_RED)
      end
    end
  end
rescue ex : MCPRuntimeError | MCPValueError
  print_color("MCP ERROR: #{ex.message}", COLOR_RED)
  exit(1)
rescue ex : IO::Error
  print_color("IO ERROR: #{ex.message}", COLOR_RED)
  exit(1)
rescue ex : Exception
  print_color("UNEXPECTED ERROR: #{ex.class.name} - #{ex.message}", COLOR_RED)
  ex.backtrace.each { |line| STDERR.puts "  #{line}" }
  exit(1)
ensure
  # Exit and cleanup
  if client && client.initialized?
    print_color("Sending exit notification and cleaning up...", COLOR_CYAN)
    client.exit
    print_color("Client exited, transport closed.", COLOR_GREEN)
  elsif transport
    print_color("Closing transport...", COLOR_CYAN)
    transport.close
  end

  print_divider("=", 70, COLOR_BLUE)
  print_color("REPL CLIENT FINISHED", COLOR_BLUE, true)
  print_divider("=", 70, COLOR_BLUE)
end
