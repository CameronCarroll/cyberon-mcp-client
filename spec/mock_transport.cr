# spec/mock_transport.cr
require "../src/transport"
require "../src/errors" # For MCPError types if needed

# Custom error for unexpected requests in tests
class UnexpectedRequestError < Exception
  def initialize(message : String)
    super("MockTransport: #{message}")
  end
end

class MockTransport
  include CyberonMCP::Transport

  # Stores expected request JSON -> response JSON or Exception
  @expectations : Hash(String, String | Exception)
  # Stores requests actually received
  @received_requests : Array(String)
  # For tracking if close was called
  @closed : Bool = false

  def initialize
    @expectations = {} of String => String | Exception
    @received_requests = [] of String
  end

  # Define an expected request and its corresponding response or error
  def expect(request_json : String, response_or_error : String | Exception)
    @expectations[request_json] = response_or_error
  end

  # The core mock method
  def send_and_receive(message : String) : String
    if @closed
      raise IO::Error.new("MockTransport: Attempted to use closed transport")
    end
    
    @received_requests << message

    response_or_error = @expectations[message]?
    unless response_or_error
      raise UnexpectedRequestError.new("Received unexpected request: #{message}. Expected one of: #{@expectations.keys.join(", ")}")
    end

    case response_or_error
    when String
      return response_or_error
    when Exception
      raise response_or_error
    else
      # Should not happen with the type restriction, but defensive programming
      raise "MockTransport: Invalid expectation type for request '#{message}'"
    end
  end

  # Implement close method required by Transport interface
  def close
    @closed = true
  end
  
  # Check if close was called
  def closed?
    @closed
  end

  # Helper to check if a specific request was received (useful for notifications)
  def received?(request_json : String) : Bool
    @received_requests.includes?(request_json)
  end

  # Optional: Verify all expectations were met (use after test actions)
  # def verify
  #   expected_keys = @expectations.keys.sort
  #   received_keys = @received_requests.uniq.sort
  #   unless expected_keys == received_keys
  #      raise "MockTransport: Not all expectations were met. Expected: #{expected_keys}, Received: #{received_keys}"
  #   end
  # end

  # Reset expectations and received requests between tests
  def reset
     @expectations.clear
     @received_requests.clear
     @closed = false
  end
  
  # Clear only received requests but keep expectations
  def reset_received
     @received_requests.clear
  end
end