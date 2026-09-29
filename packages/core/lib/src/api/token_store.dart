/// Holds the bearer token for the running session. Memory only: the token is
/// never written to disk, so closing the app signs the user out.
class TokenStore {
  String? _token;

  String? get token => _token;
  bool get hasToken => _token != null;

  void save(String token) => _token = token;

  void clear() => _token = null;
}
