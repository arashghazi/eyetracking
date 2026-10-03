namespace EyeTracking.Domain;

/// <summary>Base class for rule violations raised by domain or application code.
/// The web layer maps each kind to an HTTP status and returns the message as <c>detail</c>.</summary>
public abstract class DomainError(string message) : Exception(message);

/// <summary>404</summary>
public sealed class NotFound(string message) : DomainError(message);

/// <summary>403</summary>
public sealed class Forbidden(string message) : DomainError(message);

/// <summary>409</summary>
public sealed class Conflict(string message) : DomainError(message);

/// <summary>422</summary>
public sealed class Invalid(string message) : DomainError(message);

/// <summary>401</summary>
public sealed class AuthenticationFailed(string message) : DomainError(message);
