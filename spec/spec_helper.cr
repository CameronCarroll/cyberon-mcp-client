# spec/spec_helper.cr
require "spec"

# Adjust path based on where you run 'crystal spec' from
# Assuming you run it from the project root where 'src/' and 'spec/' reside.
require "../src/errors"
require "../src/transport"
require "../src/mcp_client"
# Feature modules are included by mcp_client.cr, no need to require them individually here

# Add a special macro to help with test expectations
macro expect_not_raises
  begin
    {{yield}}
  rescue e
    fail("Expected no exception, but got: #{e.message}")
  end
end

# Helper for testing
def relative_path(path : String) : String
  File.expand_path(path, Dir.current)
end

# Setup logging for tests
Log.setup_from_env(default_level: Log::Severity::Error)

# Configure silence for the server path in ProcessTransport tests
# This is the path to a test file that will be used by ProcessTransport
MOCK_SERVER_SCRIPT = File.expand_path("../spec/mock_server.cr", __DIR__)