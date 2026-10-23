"""Validate bounded manual GitHub workflows and native-run signing provenance."""
from pathlib import Path
import argparse
import json
import re

NATIVE_WORKFLOW = ".github/workflows/atma-ios-check.yml"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_workflow(config, *, signing):
    require(set(config["on"]) == {"workflow_dispatch"}, "Only manual GitHub runs are allowed")
    require(set(config["jobs"]) == {"ios"}, "Unexpected GitHub job")
    job = config["jobs"]["ios"]
    require(job["runs-on"] == "macos-26", "Use the standard public-repository Mac runner")
    require(job["timeout-minutes"] == 30, "Mac job must be bounded to 30 minutes")
    expected_permissions = {"contents": "read", **({"actions": "read"} if signing else {})}
    require(config["permissions"] == expected_permissions and "permissions" not in job,
            "GitHub job must not gain write permissions")
    require(job["env"]["DEVELOPER_DIR"] == "/Applications/Xcode_26.4.app/Contents/Developer",
            "Expected Xcode 26.4 image")
    steps = job["steps"]
    for row in steps:
        if "uses" in row:
            require(re.fullmatch(r"actions/[a-z-]+@[a-f0-9]{40}", row["uses"]), "Actions must be pinned")
            if row["uses"].startswith("actions/upload-artifact@"):
                require(row["with"]["retention-days"] == 1, "Keep artifacts for one day")
    scripts = [row["run"] for row in steps if "run" in row]
    require("bash release/ci.sh prepare" in scripts, "Reuse source validation and project generation")
    if signing:
        gate = next((i for i, s in enumerate(scripts) if "github_ci.py gate" in s), None)
        require(gate is not None and "bash release/ci.sh gate" in scripts
                and "bash release/ci.sh archive" in scripts, "Missing signed-build provenance gate")
        require(gate < scripts.index("bash release/ci.sh gate")
                < scripts.index("bash release/ci.sh prepare") < scripts.index("bash release/ci.sh archive"),
                "Verification must precede prepare/archive")
        publishing = [row for row in steps if "publish --path" in row.get("run", "")]
        require(len(publishing) == 1 and publishing[0].get("if") == "$" + "{{ inputs.upload_to_testflight }}",
                "Binary upload needs an explicit input")
        require(not re.search(r"--(?:testflight|app-store)\b", publishing[0]["run"]),
                "Automatic beta/App Store review submission is not allowed")
        require(config["on"]["workflow_dispatch"]["inputs"]["upload_to_testflight"]["default"] is False,
                "Upload cannot be enabled by default")
    else:
        require("bash release/ci.sh smoke" in scripts, "Both native devices must be checked")
        require("secrets." not in json.dumps(config), "Native checks must not receive signing secrets")


def verify_run(run, *, repository, run_id, revision, verified_revision):
    require(bool(re.fullmatch(r"[1-9][0-9]*", run_id)), "Expected a GitHub native run ID")
    require(bool(re.fullmatch(r"[a-f0-9]{40}", revision)), "Expected an exact source commit SHA")
    require(str(run.get("id")) == run_id, "Native run ID differs")
    require(run.get("repository", {}).get("full_name") == repository, "Native run belongs to another repository")
    workflow_path = str(run.get("path", "")).partition("@")[0]
    require(run.get("event") == "workflow_dispatch" and workflow_path == NATIVE_WORKFLOW,
            "Expected the manual ATMA iPhone/iPad workflow")
    require(run.get("status") == "completed" and run.get("conclusion") == "success",
            "Native iPhone/iPad workflow must have succeeded")
    require(verified_revision.strip() == revision, "Verified native source does not match archive source")
    return revision


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["gate"])
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--verified", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    print(verify_run(json.loads(args.run.read_text(encoding="utf-8")),
                     repository=args.repository, run_id=args.run_id, revision=args.revision,
                     verified_revision=args.verified.read_text(encoding="utf-8")))
