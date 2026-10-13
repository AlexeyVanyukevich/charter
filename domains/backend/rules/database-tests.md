# Database tests

**Integration tests run against a real PostgreSQL, started by Testcontainers.** The guarantees
that matter — constraints, row locking, timezone arithmetic — cannot be verified against a
mock, and a suite that mocks them proves only that the mock agrees with itself.
