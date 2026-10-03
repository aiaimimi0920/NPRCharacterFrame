"""Same counts never substitute for complete OSV result identity coverage."""
import copy
import hashlib
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sarif_coverage import CoverageError, validate_coverage

class CoverageTests(unittest.TestCase):
    def fixture(self):
        primary, alias = "GHSA-fixture-id", "CVE-2020-1234"
        document = {"results": []}
        results = []
        for uri, version in [("package-lock.json", "1.0.0"), ("scripts/package-lock.json", "2.0.0")]:
            document["results"].append({"source": {"type": "lockfile", "path": "/github/workspace/" + uri},
              "packages": [{"package": {"name": "sample", "version": version, "ecosystem": "npm"},
                "vulnerabilities": [{"id": primary, "aliases": [alias]}],
                "groups": [{"ids": [primary]}]}]})
            fingerprint = hashlib.sha256((alias + ":" + uri + ":sample@" + version).encode()).hexdigest()
            results.append({"ruleId": alias, "ruleIndex": 0,
              "message": {"text": "Package 'sample@" + version + "' is vulnerable to '" + alias + "' (also known as '" + primary + "')."},
              "locations": [{"physicalLocation": {"artifactLocation": {"uri": uri}}}],
              "partialFingerprints": {"primaryLocationLineHash": fingerprint}})
        sarif = {"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "osv-scanner", "version": "2.5.1",
                   "rules": [{"id": alias, "deprecatedIds": [alias, primary]}]}}, "results": results}]}
        return document, sarif
    def test_same_advisory_at_two_versions_and_locks_remains_two_findings(self):
        document, sarif = self.fixture()
        report = validate_coverage(document, sarif)
        self.assertTrue(report["sarif_identity_complete"])
        self.assertEqual(report["covered_package_occurrences"], 2)
        self.assertEqual(report["covered_alias_ids"], 2)
    def test_order_does_not_change_coverage(self):
        document, sarif = self.fixture()
        sarif["runs"][0]["results"].reverse()
        self.assertEqual(validate_coverage(document, sarif)["covered_package_occurrences"], 2)
    def test_zero_findings_still_requires_valid_inventory(self):
        document, sarif = self.fixture()
        for source in document["results"]:
            source["packages"][0].update(vulnerabilities=[], groups=[])
        sarif["runs"][0]["results"] = []
        sarif["runs"][0]["tool"]["driver"]["rules"] = []
        self.assertEqual(validate_coverage(document, sarif)["covered_package_occurrences"], 0)
    def test_same_count_different_package_version_uri_or_fingerprint_fails(self):
        for mode in ["package", "version", "uri", "fingerprint", "duplicate", "rule"]:
            document, sarif = self.fixture()
            row = sarif["runs"][0]["results"][0]
            if mode == "package":
                row["message"]["text"] = row["message"]["text"].replace("sample@", "other@")
            elif mode == "version":
                row["message"]["text"] = row["message"]["text"].replace("1.0.0", "9.0.0")
            elif mode == "uri":
                row["locations"][0]["physicalLocation"]["artifactLocation"]["uri"] = "other-lock.json"
            elif mode == "fingerprint":
                row["partialFingerprints"]["primaryLocationLineHash"] = "0" * 64
            elif mode == "duplicate":
                sarif["runs"][0]["results"][1] = copy.deepcopy(row)
            else:
                row["ruleId"] = "GHSA-unrelated"
            with self.subTest(mode=mode), self.assertRaises(CoverageError):
                validate_coverage(document, sarif)
    def test_missing_or_extra_alias_is_not_coverage(self):
        for mode in ["missing", "extra"]:
            document, sarif = self.fixture()
            ids = sarif["runs"][0]["tool"]["driver"]["rules"][0]["deprecatedIds"]
            if mode == "missing":
                ids.pop()
            else:
                ids.append("GHSA-unrelated")
            with self.assertRaises(CoverageError):
                validate_coverage(document, sarif)
    def test_one_missing_fingerprint_or_wrong_rule_index_fails(self):
        for mode in ["missing", "rule_index"]:
            document, sarif = self.fixture()
            row = sarif["runs"][0]["results"][0]
            if mode == "missing":
                del row["partialFingerprints"]
            else:
                row["ruleIndex"] = 7
            with self.assertRaises(CoverageError):
                validate_coverage(document, sarif)
    def test_changed_scanner_package_version_cannot_reuse_old_sarif(self):
        document, sarif = self.fixture()
        document["results"][0]["packages"][0]["package"]["version"] = "3.0.0"
        with self.assertRaises(CoverageError):
            validate_coverage(document, sarif)

    def test_vendor_alias_group_multiplicity_preserves_all_rows(self):
        document, sarif = self.fixture()
        alias_id = "GHSA-second-primary"
        for source in document["results"]:
            entry = source["packages"][0]
            entry["vulnerabilities"].append({"id": alias_id, "aliases": ["CVE-2020-1234"]})
            entry["groups"][0]["ids"].append(alias_id)
        run = sarif["runs"][0]
        run["tool"]["driver"]["rules"][0]["deprecatedIds"].append(alias_id)
        for row in run["results"]:
            row["message"]["text"] = row["message"]["text"].replace("').", "', '" + alias_id + "').")
        run["results"] += copy.deepcopy(run["results"])
        report = validate_coverage(document, sarif)
        self.assertEqual(report["covered_sarif_rows"], 4)
        self.assertEqual(report["covered_package_occurrences"], 2)
        for mode in ["missing", "extra", "replace"]:
            bad = copy.deepcopy(sarif)
            rows = bad["runs"][0]["results"]
            if mode == "missing":
                rows.pop()
            elif mode == "extra":
                rows.append(copy.deepcopy(rows[0]))
            else:
                rows[1] = copy.deepcopy(rows[0])
            with self.subTest(mode=mode), self.assertRaises(CoverageError):
                validate_coverage(document, bad)

if __name__ == "__main__":
    unittest.main(verbosity=2)
