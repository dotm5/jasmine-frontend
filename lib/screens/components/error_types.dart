const ERROR_TYPE_NETWORK = "NETWORK_ERROR";
const ERROR_TYPE_PERMISSION = "PERMISSION_ERROR";
const ERROR_TYPE_TIME = "TIME_ERROR";
const ERROR_TYPE_UNDER_REVIEW = "UNDER_VIEW_ERROR";

// Keep technical details available while showing a useful, concise summary.
String errorType(String error) {
  error = error.toLowerCase();
  if (error.contains("timeout") ||
      error.contains("connection refused") ||
      error.contains("deadline") ||
      error.contains("connection abort") ||
      error.contains("socketexception") ||
      error.contains("failed host lookup") ||
      error.contains("dns error") ||
      error.contains("network is unreachable")) {
    return ERROR_TYPE_NETWORK;
  }
  if (error.contains("permission denied")) return ERROR_TYPE_PERMISSION;
  if (error.contains("time is not synchronize")) return ERROR_TYPE_TIME;
  if (error.contains("under review")) return ERROR_TYPE_UNDER_REVIEW;
  return "";
}
