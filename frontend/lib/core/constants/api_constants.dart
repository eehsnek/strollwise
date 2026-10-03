class ApiConstants {
  /// Base URL of the StrollWise backend (local uvicorn on port 8000 by default).
  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// All HTTP calls are prefixed with this path (matches `api_v1_prefix`
  /// in the backend settings).
  static const apiPrefix = '/api/v1';
}
