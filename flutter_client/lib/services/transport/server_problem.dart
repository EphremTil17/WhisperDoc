/// Why the last connection attempt never reached a server that would talk.
/// A rejected sign-in is not one of these: the server answered.
enum ServerProblem {
  /// The last attempt reached a server, or none has been made yet.
  none,

  /// Nothing answered: the server is down, its container is stopped, or the
  /// network can't reach it.
  unreachable,

  /// The address was refused before connecting: plain ws:// to a server
  /// outside the local network.
  insecure,
}
