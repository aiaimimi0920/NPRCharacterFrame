"""Check OSV 2.5.1 SARIF aliases and each package/version/lock fingerprint."""
import hashlib
import re
from collections import Counter

LIMIT = 100_000

class CoverageError(ValueError):
    pass

def require(condition, code):
    if not condition:
        raise CoverageError(code)

def identifier(value):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.:-]{1,160}", value), "invalid_advisory_id")
    return value

def ordered_ids(values):
    priority = {"DSA": 3, "USN": 3, "CVE": 2, "GHSA": 0}
    return sorted(values, key=lambda value: (-priority.get(value.split("-")[0], 1), value))

def package_label(package):
    name, version = package.get("name"), package.get("version")
    require(isinstance(name, str) and bool(name) and isinstance(version, str), "invalid_package_identity")
    commit = package.get("commit", "")
    require(isinstance(commit, str), "invalid_package_identity")
    return name + "@" + (commit[:8] if commit else version)

def expected_findings(document):
    sources = document.get("results")
    require(isinstance(sources, list) and bool(sources), "missing_package_inventory")
    parent, rows = {}, []
    def find(key):
        parent.setdefault(key, key)
        while parent[key] != key:
            parent[key] = parent[parent[key]]
            key = parent[key]
        return key
    def union(left, right):
        parent[find(right)] = find(left)
    for source in sources:
        uri = source["source"]["path"]
        require(isinstance(uri, str) and uri.startswith("/github/workspace/"), "unexpected_lock_uri")
        uri = uri[len("/github/workspace/"):]
        require(uri and not uri.startswith("/") and ".." not in uri.split("/"), "unexpected_lock_uri")
        for entry in source["packages"]:
            package = entry["package"]
            label = package_label(package)
            vulnerabilities = {identifier(v["id"]): v for v in entry.get("vulnerabilities", [])}
            grouped = set()
            for group in entry.get("groups", []):
                ids = group["ids"]
                require(isinstance(ids, list) and bool(ids) and len(ids) <= LIMIT, "invalid_alias_group")
                ids = [identifier(value) for value in ids]
                for value in ids:
                    union(ids[0], value)
                aliases = set()
                for value in ids:
                    if value not in vulnerabilities:
                        continue
                    vulnerability = vulnerabilities[value]
                    extra = vulnerability.get("aliases", [])
                    require(isinstance(extra, list), "invalid_alias_group")
                    aliases.add(value)
                    aliases.update(identifier(alias) for alias in extra)
                require(bool(aliases), "unrepresented_alias_group")
                grouped.update(ids)
                rows.append((ids[0], uri, label, package["ecosystem"], frozenset(aliases)))
            require(set(vulnerabilities) <= grouped, "unrepresented_vulnerability")
    require(len(rows) <= LIMIT, "result_limit_exceeded")
    aliases_by_group = {}
    for group, uri, label, ecosystem, aliases in rows:
        aliases_by_group.setdefault(find(group), set()).update(aliases)
    expected, rules = {}, {}
    primary_ids = Counter(find(value) for value in parent)
    for group, uri, label, ecosystem, aliases in rows:
        full_aliases = aliases_by_group[find(group)]
        display = ordered_ids(full_aliases)[0]
        rules.setdefault(display, set()).update(full_aliases)
        fingerprint = hashlib.sha256((display + ":" + uri + ":" + label).encode("utf-8")).hexdigest()
        identity = (display, uri, fingerprint)
        semantic = (label, ecosystem, find(group), primary_ids[find(group)])
        require(identity not in expected or expected[identity] == semantic, "ambiguous_finding_identity")
        expected[identity] = semantic
    return expected, rules

def expected_row_count(document):
    # OSV 2.5.1 emits a complete group once for every primary ID mapped to it.
    expected, _ = expected_findings(document)
    return sum(value[3] for value in expected.values())

def validate_coverage(document, sarif):
    expected, rules_expected = expected_findings(document)
    runs = sarif.get("runs")
    require(isinstance(runs, list) and len(runs) == 1, "invalid_sarif_runs")
    run = runs[0]
    rules = run.get("tool", {}).get("driver", {}).get("rules", [])
    require(isinstance(rules, list) and len(rules) <= LIMIT, "invalid_sarif_rules")
    actual_rules = {}
    for rule in rules:
        require(isinstance(rule, dict), "invalid_sarif_rule")
        name = identifier(rule.get("id"))
        aliases = rule.get("deprecatedIds")
        require(isinstance(aliases, list) and len(aliases) <= LIMIT, "missing_sarif_aliases")
        alias_set = {identifier(alias) for alias in aliases}
        require(name in alias_set and len(alias_set) == len(aliases), "invalid_sarif_aliases")
        require(name not in actual_rules or actual_rules[name] == alias_set, "conflicting_sarif_rule")
        actual_rules[name] = alias_set
    require(actual_rules == rules_expected, "sarif_alias_coverage_mismatch")
    results = run.get("results")
    required = Counter({identity: value[3] for identity, value in expected.items()})
    require(isinstance(results, list) and len(results) == sum(required.values()), "sarif_identity_count_mismatch")
    covered = Counter()
    for result in results:
        require(isinstance(result, dict), "invalid_sarif_result")
        rule = identifier(result.get("ruleId"))
        index = result.get("ruleIndex")
        if index is not None:
            require(type(index) is int and 0 <= index < len(rules)
                    and rules[index]["id"] == rule, "invalid_sarif_rule_index")
        locations = result.get("locations")
        require(isinstance(locations, list) and len(locations) == 1, "invalid_sarif_lock_location")
        uri = locations[0].get("physicalLocation", {}).get("artifactLocation", {}).get("uri")
        require(isinstance(uri, str), "missing_sarif_lock_uri")
        fingerprints = result.get("partialFingerprints")
        require(isinstance(fingerprints, dict), "missing_sarif_fingerprint")
        fingerprint = fingerprints.get("primaryLocationLineHash")
        require(isinstance(fingerprint, str) and re.fullmatch(r"[a-f0-9]{64}", fingerprint), "invalid_sarif_fingerprint")
        identity = (rule, uri, fingerprint)
        require(identity in expected and covered[identity] < required[identity], "sarif_package_version_uri_fingerprint_mismatch")
        label = expected[identity][0]
        aliases = ordered_ids(actual_rules[rule])
        suffix = " (also known as '" + "', '".join(aliases[1:]) + "')" if len(aliases) > 1 else ""
        message = "Package '" + label + "' is vulnerable to '" + rule + "'" + suffix + "."
        require(result.get("message", {}).get("text") == message, "sarif_package_message_mismatch")
        covered[identity] += 1
    require(covered == required, "incomplete_sarif_identity_coverage")
    return {"sarif_identity_complete": True, "covered_package_occurrences": len(covered),
            "covered_sarif_rows": sum(covered.values()),
            "covered_alias_ids": len({alias for values in actual_rules.values() for alias in values})}
