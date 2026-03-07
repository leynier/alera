/// JSON-RPC 2.0 standard error codes.
///
/// See https://www.jsonrpc.org/specification#error_object
library;

/// Invalid JSON was received by the server.
/// An error occurred on the server while parsing the JSON text.
const jsonRpcParseError = -32700;

/// The JSON sent is not a valid Request object.
const jsonRpcInvalidRequest = -32600;

/// The method does not exist or is not available.
const jsonRpcMethodNotFound = -32601;

/// Invalid method parameter(s).
const jsonRpcInvalidParams = -32602;

/// Internal JSON-RPC error.
const jsonRpcInternalError = -32603;

/// Server error base range (-32000 to -32099).
/// Reserved for implementation-defined server-errors.
const jsonRpcServerErrorBase = -32000;
