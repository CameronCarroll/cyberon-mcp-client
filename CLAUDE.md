# Cyberon MCP Client Development Guide

## Build Commands
- Run all tests: `crystal spec`
- Run a single test: `crystal spec spec/file_name_spec.cr:LINE_NUMBER`
- Run specific test file: `crystal spec spec/file_name_spec.cr`
- Format code: `crystal tool format`

## Code Style Guidelines
- Use 2-space indentation
- Use snake_case for method names and variables
- Use CamelCase for class and module names
- Error handling: Use specific error classes from `src/errors.cr`
- Type parameters should have clear, descriptive names
- Prefer named arguments for clarity on method calls

## Implementation Details
- All communication between client and server is JSON-RPC 2.0
- Mock server is implemented in Python for testing (see spec/mock_server.cr)
- The client expects `clientInfo` (camelCase) in JSON, not `client_info` in parameters
- When adding new features, add them to a module in src/client/features/