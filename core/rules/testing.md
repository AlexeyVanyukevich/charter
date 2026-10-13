# Testing

**Tests are written before the implementation, for every slice.**

**Test data lives in datasets, not in test bodies.** One behaviour's cases — one call, checked
one way — go in a typed table a parameterised runner reads: more coverage is a row, not a copied
test. A different behaviour is its own test, and a scenario stays a scenario. A value that *is*
the point — a real DST transition, a boundary — is a named row carrying its expectation.

**Facts about the outside world are derived, not remembered.** A date that came from the tz
database is regenerated from it; a constant transcribed by hand is a constant that goes stale
without anyone noticing.

Pure functions get unit tests. Anything with a clock or a network takes them as an injected
dependency, because otherwise every threshold, cooldown and backoff test has to sleep in real
time.

Tests live in `tests/unit/` and `tests/integration/`, browser journeys in `tests/ui/`.
