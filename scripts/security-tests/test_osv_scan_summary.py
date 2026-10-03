"""Synthetic OSV failures must never become advisory findings."""
import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from osv_scan_summary import classify_osv
import test_sarif_coverage as coverage_fixtures

class SummaryTests(unittest.TestCase):
    def fixture(self):
        return coverage_fixtures.CoverageTests().fixture()
    def classify(self, document, sarif, scan=1, report=1, advisory=True):
        return classify_osv(document, sarif, scan, report,
                            ["package-lock.json", "scripts/package-lock.json"], advisory)
    def test_valid_findings_are_retained_in_advisory(self):
        document, sarif = self.fixture()
        facts, status = self.classify(document, sarif)
        self.assertEqual(status, 0)
        self.assertEqual(facts["scanner_exit"], 1)
        self.assertEqual(facts["vulnerability_records"], 2)
        self.assertEqual(facts["sarif_result_count"], 2)
        self.assertTrue(facts["analysis_complete"])
        self.assertEqual(self.classify(document, sarif, advisory=False)[1], 1)
    def test_raw_execution_error_stays_error(self):
        document, sarif = self.fixture()
        for status in (2, 124, 127, 128, 130, -1):
            with self.assertRaises(ValueError):
                self.classify(document, sarif, scan=status)
    def test_zero_status_with_findings_is_error(self):
        document, sarif = self.fixture()
        with self.assertRaises(ValueError):
            self.classify(document, sarif, scan=0, report=0)
    def test_reporter_failure_stays_error(self):
        document, sarif = self.fixture()
        with self.assertRaises(ValueError):
            self.classify(document, sarif, report=2)
    def test_missing_selected_lock_stays_error(self):
        document, sarif = self.fixture()
        document["results"].pop()
        with self.assertRaises(ValueError):
            self.classify(document, sarif)
    def test_same_count_different_package_stays_error(self):
        document, sarif = self.fixture()
        sarif["runs"][0]["results"][0]["partialFingerprints"]["primaryLocationLineHash"] = "0" * 64
        with self.assertRaises(ValueError):
            self.classify(document, sarif)
    def test_sarif_failed_invocation_stays_error(self):
        document, sarif = self.fixture()
        sarif["runs"][0]["invocations"] = [{"executionSuccessful": False}]
        with self.assertRaises(ValueError):
            self.classify(document, sarif)
    def test_sarif_error_notification_is_invalid(self):
        for field in ("toolExecutionNotifications", "toolConfigurationNotifications"):
            document, sarif = self.fixture()
            sarif["runs"][0]["invocations"] = [{"executionSuccessful": True,
                field: [{"level": "error", "message": {"text": "FIXTURE"}}]}]
            with self.assertRaises(ValueError):
                self.classify(document, sarif)
    def test_sarif_execution_flag_must_be_boolean_true(self):
        for invocation in ({}, {"executionSuccessful": "true"}, {"executionSuccessful": 1}):
            document, sarif = self.fixture()
            sarif["runs"][0]["invocations"] = [invocation]
            with self.assertRaises(ValueError):
                self.classify(document, sarif)
    def test_sarif_invocations_can_be_absent_or_valid(self):
        document, sarif = self.fixture()
        self.assertEqual(self.classify(document, sarif)[1], 0)
        sarif["runs"][0]["invocations"] = [{"executionSuccessful": True,
            "toolExecutionNotifications": [{"level": "warning"}]}]
        self.assertEqual(self.classify(document, sarif)[1], 0)
    def test_clean_complete_inventory_is_zero(self):
        document, sarif = self.fixture()
        for source in document["results"]:
            for entry in source["packages"]:
                entry["vulnerabilities"] = []
                entry["groups"] = []
        sarif["runs"][0]["results"] = []
        sarif["runs"][0]["tool"]["driver"]["rules"] = []
        self.assertEqual(self.classify(document, sarif, scan=0, report=0)[1], 0)

if __name__ == "__main__":
    unittest.main()
