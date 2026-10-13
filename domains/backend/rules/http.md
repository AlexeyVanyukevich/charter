---
paths:
  - "src/*"
  - "src/modules/**"
  - "src/shared/**"
---
# HTTP

Every error response has the same shape, whatever produced it:

    { "error": "validation_error", "message": "…", "details": {} }

`details` is optional. `error` is the vocabulary the interface reads; `message` is for the log
and the test suite, and is never shown to a user.

| Code                | Status | Meaning                                          |
| ------------------- | ------ | ------------------------------------------------ |
| `validation_error`  | 400    | Body, query or path failed validation            |
| `bad_request`       | 4xx    | A framework 4xx with no better code              |
| `unauthorized`      | 401    | Missing, malformed, unknown or revoked credential |
| `forbidden_origin`  | 403    | A write whose `Origin` is not the app's own      |
| `not_found`         | 404    | No such record, or no such route                 |
| `conflict`          | 409    | The request lost a race it can retry             |
| `payload_too_large` | 413    | Body beyond the configured limit                 |
| `internal_error`    | 500    | Anything unexpected                              |

**Every request body is validated against a schema that rejects unknown fields.** A field the
server silently drops is a feature the client believes it has.

**Framework-level 4xx are translated into this shape too.** A caller's mistake must never
surface as `internal_error`.

**Every authentication failure answers identically,** whatever actually went wrong.
Distinguishing "no such key" from "wrong secret" turns enumeration into a usable probe.

**Unexpected exceptions are logged with their stack and returned bare.** Database structure
never reaches a client through error text.
