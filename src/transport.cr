# src/transport.cr
require "json"
require "log"
require "./errors" # Assuming errors.cr is in the same directory or adjust path

# A module defining the Transport interface for MCP communications
module CyberonMCP
  module Transport
    abstract def send_and_receive(message : String) : String
    abstract def close
  end

  # An implementation of Transport using standard input/output
  class StdioTransport
    include Transport

    # Logger instance for logging transport activities
    class_getter logger = Log.for("mcp_transport.stdio")

    # IO objects for communication
    @input_io : IO
    @output_io : IO
    @owns_io : Bool

    # Initialize with default or custom IO objects
    def initialize(input_io : IO = STDIN, output_io : IO = STDOUT, owns_io : Bool = false)
      @input_io = input_io
      @output_io = output_io
      @owns_io = owns_io

      # Ensure immediate flushing if output is STDOUT
      STDOUT.sync = true if output_io == STDOUT

      self.class.logger.debug { "StdioTransport initialized with input: #{input_io.class}, output: #{output_io.class}" }
    end

    def send_and_receive(message : String) : String
      begin
        self.class.logger.debug { "Sending message: #{message}" }
        @output_io.puts(message)
        @output_io.flush

        response = @input_io.gets
        self.class.logger.debug { "Received response: #{response}" }

        if response.nil?
          self.class.logger.error { "IO closed unexpectedly." }
          raise IO::Error.new("End of stream reached while waiting for response.")
        end

        return response.strip
      rescue ex : Exception
        self.class.logger.error { "StdioTransport Error: #{ex.message}" }
        # Construct a JSON-RPC error response
        error_response = {
          jsonrpc: "2.0",
          id:      nil,
          error:   {
            code:    -32000, # Generic transport error
            message: "Transport error: Failed to send/receive message via stdio",
            data:    ex.message,
          },
        }
        return error_response.to_json
      end
    end

    # Close the IO streams if we own them
    def close
      if @owns_io
        begin
          @output_io.close unless @output_io == STDOUT
          self.class.logger.debug { "Output IO closed" }
        rescue ex
          self.class.logger.warn { "Error closing output IO: #{ex.message}" }
        end

        begin
          @input_io.close unless @input_io == STDIN
          self.class.logger.debug { "Input IO closed" }
        rescue ex
          self.class.logger.warn { "Error closing input IO: #{ex.message}" }
        end
      end
    end
  end

  # An implementation of Transport that manages a server process
  class ProcessTransport
    include Transport

    # Logger instance for logging transport activities
    class_getter logger = Log.for("mcp_transport.process")

    # The server process
    @process : Process?
    @server_path : String
    @stderr_fiber : Fiber?
    @transport : StdioTransport?

    # Colors for terminal output
    RESET  = "\033[0m"
    YELLOW = "\033[33m"
    RED    = "\033[31m"
    GREEN  = "\033[32m"

    # Initialize with the path to the server script
    def initialize(@server_path : String, @shell : Bool = false)
      self.class.logger.info { "ProcessTransport initialized with server path: #{@server_path}" }

      # Validate that server script exists
      unless File.exists?(@server_path)
        raise IO::Error.new("Server script not found at: #{@server_path}")
      end
    end

    # Launch the server process
    def launch_server : Bool
      if @process
        self.class.logger.warn { "Server process already running. Use close() first." }
        return false
      end

      self.class.logger.info { "Launching MCP server process from: #{@server_path}" }
      begin
        # Spawn the server process with redirected IO
        cmd = @shell ? @server_path : "python #{@server_path}"
        @process = Process.new(
          cmd,
          shell: true,
          input: :pipe,
          output: :pipe,
          error: :pipe
        )

        process = @process.not_nil!
        self.class.logger.info { "Server process launched with PID: #{process.pid}" }

        # Create a fiber to read and log stderr
        @stderr_fiber = spawn do
          stderr_reader(process.error)
        end

        # Create a StdioTransport using the process IO
        @transport = StdioTransport.new(
          input_io: process.output,
          output_io: process.input,
          owns_io: true
        )

        return true
      rescue ex
        self.class.logger.error { "Failed to launch server process: #{ex.message}" }
        raise IO::Error.new("Failed to launch server process: #{ex.message}")
      end
    end

    # Fiber function to read and log stderr
    private def stderr_reader(error_io : IO)
      self.class.logger.debug { "Started stderr reader fiber" }
      begin
        while line = error_io.gets
          STDERR.puts "#{YELLOW}[Server STDERR]#{RESET}: #{line}"
        end
      rescue ex
        STDERR.puts "#{RED}[Server STDERR Reader Error]#{RESET}: #{ex.message}"
      ensure
        STDERR.puts "#{YELLOW}[Server STDERR]#{RESET}: Stream closed."
      end
    end

    # Delegate send_and_receive to the StdioTransport
    def send_and_receive(message : String) : String
      transport = @transport
      unless transport
        raise IO::Error.new("Process transport not initialized. Call launch_server() first.")
      end

      transport.send_and_receive(message)
    end

    # Close the transport and terminate the server process
    def close
      transport = @transport
      if transport
        transport.close
        @transport = nil
      end

      process = @process
      if process
        self.class.logger.info { "Terminating server process (PID: #{process.pid})..." }

        # Check if process is still running
        status = process.exists?
        if status
          begin
            # Try graceful termination first
            self.class.logger.debug { "Sending TERM signal to process..." }
            process.terminate

            # Wait a short time for graceful shutdown
            start_time = Time.monotonic
            while process.exists? && (Time.monotonic - start_time < 2.seconds)
              sleep(0.1.seconds)
            end

            # If still running, send KILL signal
            if process.exists?
              self.class.logger.warn { "Process did not terminate gracefully, sending KILL signal..." }
              # Use Signal::KILL instead of process.kill
              Process.signal(Signal::KILL, process.pid)
              process.wait
            else
              self.class.logger.info { "Process terminated gracefully." }
            end
          rescue ex
            self.class.logger.error { "Error during process termination: #{ex.message}" }
          end
        else
          self.class.logger.info { "Process already terminated." }
        end

        # Close error stream
        begin
          process.error.close
        rescue
          # Ignore errors closing error stream
        end

        # Wait for the stderr fiber to finish
        if @stderr_fiber
          begin
            Fiber.yield # Give the fiber a chance to finish
          rescue
            # Ignore fiber errors
          end
        end

        @process = nil
        self.class.logger.info { "Server process cleanup complete." }
      end
    end

    # Check if the server process is still running
    def server_alive? : Bool
      process = @process
      return false unless process
      process.exists?
    end
  end
end
