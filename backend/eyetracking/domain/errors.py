class DomainError(Exception):
    """Base class for rule violations raised by domain or application code."""


class NotFound(DomainError):
    pass


class Forbidden(DomainError):
    pass


class Conflict(DomainError):
    pass


class Invalid(DomainError):
    pass


class AuthenticationFailed(DomainError):
    pass
