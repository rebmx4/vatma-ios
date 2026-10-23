"""Guards for manual workflows and exact native verification provenance."""
from pathlib import Path
import json
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "release"))
from github_ci import validate_workflow, verify_run


class WorkflowTests(unittest.TestCase):
    def config(self, filename):
        return json.loads((ROOT / ".github/workflows" / filename).read_text(encoding="utf-8"))

    def test_current_workflows_are_manual_and_bounded(self):
        for filename in ("atma-ios-check.yml", "atma-testflight.yml"):
            validate_workflow(self.config(filename), signing=filename == "atma-testflight.yml")

    def test_automatic_or_paid_runner_and_long_artifact_retention_are_rejected(self):
        for change in (lambda c: c["on"].update(push={}),
                       lambda c: c["jobs"]["ios"].update({"runs-on": "macos-latest-xlarge"}),
                       lambda c: c["jobs"]["ios"].update({"timeout-minutes": 360}),
                       lambda c: c["jobs"]["ios"]["steps"][-1]["with"].update({"retention-days": 90})):
            config = self.config("atma-ios-check.yml")
            change(config)
            with self.assertRaises(ValueError):
                validate_workflow(config, signing=False)

    def test_signing_without_revision_gate_or_with_review_submission_is_rejected(self):
        config = self.config("atma-testflight.yml")
        config["jobs"]["ios"]["steps"] = [row for row in config["jobs"]["ios"]["steps"]
                                             if "github_ci.py gate" not in row.get("run", "")]
        with self.assertRaises(ValueError):
            validate_workflow(config, signing=True)
        config = self.config("atma-testflight.yml")
        next(row for row in config["jobs"]["ios"]["steps"] if "publish --path" in row.get("run", ""))["run"] += " --testflight"
        with self.assertRaises(ValueError):
            validate_workflow(config, signing=True)


class VerificationTests(unittest.TestCase):
    revision = "a" * 40
    repo = "rebmx4/vatma-ios"

    def run_data(self):
        return {"id": 123, "status": "completed", "conclusion": "success",
                "event": "workflow_dispatch", "path": ".github/workflows/atma-ios-check.yml",
                "head_sha": "b" * 40, "repository": {"full_name": self.repo}}

    def verify(self, run=None, revision=None, artifact=None):
        return verify_run(run or self.run_data(), repository=self.repo, run_id="123",
                          revision=revision or self.revision,
                          verified_revision=self.revision + "\n" if artifact is None else artifact)

    def test_verified_source_is_independent_of_registration_commit(self):
        self.assertEqual(self.verify(), self.revision)

    def test_workflow_path_can_include_documented_ref_suffix(self):
        for path in (".github/workflows/atma-ios-check.yml@main",
                     ".github/workflows/atma-ios-check.yml@refs/heads/main"):
            run = self.run_data()
            run["path"] = path
            self.assertEqual(self.verify(run=run), self.revision)

    def test_failed_foreign_automatic_wrong_workflow_or_wrong_run_is_rejected(self):
        for change in ({"conclusion": "failure"}, {"status": "in_progress"},
                       {"repository": {"full_name": "someone/other"}},
                       {"event": "push"}, {"path": ".github/workflows/other.yml"}, {"id": 124}):
            run = self.run_data()
            run.update(change)
            with self.assertRaises(ValueError):
                self.verify(run=run)

    def test_missing_mismatched_or_non_sha_artifact_is_rejected(self):
        for artifact in ("", "b" * 40, "atma-browser-testflight", "a" * 40 + "\nother"):
            with self.assertRaises(ValueError):
                self.verify(artifact=artifact)
        with self.assertRaises(ValueError):
            self.verify(revision="main")


if __name__ == "__main__":
    unittest.main()
