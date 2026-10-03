# Development security reports

PRs, the default branch and weekly schedules keep complete CodeQL and OSV
results. Findings remain advisory; scanner execution, selected-input coverage,
JSON/SARIF validation and upload failures remain failing checks. OSV JSON and
SARIF use one exact input list and validate package/version/location identities.
GitHub code-scanning fingerprints deduplicate repeated findings; check summaries
and retained artifacts are the PR report, not a claim of fixed vulnerabilities.
No Issue-writing token or automatic dependency merge is introduced.

OSV inputs:
- `.tmp/dependency-security/requirements.txt`

CodeQL languages: python, actions.
GDScript and shaders are not supported by CodeQL; no coverage is claimed for them.
The Python requirements are ranges, not a committed lock. Each scan resolves a
fresh binary-wheel-only environment and retains its exact resolved requirements.
This proves only the resolved versions, not every version allowed by the ranges.

Existing reviewed exceptions, tests, release signing and deployment gates are
unchanged. Reusable dependency scans default to strict findings for release
callers. Repository security switches require separate administrative visibility;
a workflow file does not prove that those switches are enabled.
