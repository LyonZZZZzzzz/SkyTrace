# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |
| Earlier | No |

## Reporting a Vulnerability

Do not open a public issue for security vulnerabilities.

Use the repository's **Security → Advisories → Report a vulnerability** flow.
Include:

- Affected platform and version
- Reproduction steps
- Impact and possible attack path
- Any suggested mitigation

Do not include real user locations, device identifiers, credentials, or private
data. The maintainer will acknowledge the report and coordinate a fix before
public disclosure.

## Scope

SkyTrace is an offline astronomy application. It does not operate a backend,
collect accounts, or upload observation locations. Relevant security areas
include local data handling, URL/file parsing, and dependency vulnerabilities.
