"""Static validation for Azure Data Factory artifacts (Git-integration layout).

Catches, before publish, the mistakes ADF otherwise only reports at deploy or run time:

* JSON parses and each file's ``name`` matches its filename
* every LinkedService / Dataset / Pipeline / DataFlow / IR reference resolves
* activity names are unique per pipeline, ``dependsOn`` targets exist, no cycles
* Execute Pipeline and trigger parameters exist on the target pipeline
* data flow sources / sinks / transformations are all defined in the script
* no plain-text secrets: passwords and keys must come from Key Vault

    python scripts/validate_adf.py [adf_dir]
"""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path

KINDS = {
    "linkedService": "LinkedServiceReference",
    "dataset": "DatasetReference",
    "pipeline": "PipelineReference",
    "dataflow": "DataFlowReference",
    "integrationRuntime": "IntegrationRuntimeReference",
    "trigger": None,
    "factory": None,
}
SECRET_KEYS = {"password", "accountkey", "sastoken", "servicePrincipalKey".lower(), "clientsecret"}
SECRET_PATTERNS = re.compile(r"(password|pwd|accountkey|sharedaccesskey)\s*=", re.IGNORECASE)


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    counts: dict[str, int] = field(default_factory=dict)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")


def load_artifacts(adf_dir: Path, report: Report) -> dict[str, dict[str, dict]]:
    artifacts: dict[str, dict[str, dict]] = {kind: {} for kind in KINDS}
    for kind in KINDS:
        for path in sorted((adf_dir / kind).glob("*.json")):
            where = f"{kind}/{path.name}"
            try:
                doc = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                report.error(where, f"invalid JSON ({exc})")
                continue
            if doc.get("name") != path.stem:
                report.error(where, f"name '{doc.get('name')}' does not match filename")
            artifacts[kind][doc.get("name", path.stem)] = doc
        report.counts[kind] = len(artifacts[kind])
    return artifacts


def walk(node: object) -> Iterator[dict]:
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def check_references(artifacts: dict, report: Report) -> None:
    by_type = {ref_type: kind for kind, ref_type in KINDS.items() if ref_type}
    for kind, docs in artifacts.items():
        for name, doc in docs.items():
            for node in walk(doc):
                ref_type = node.get("type")
                if ref_type in by_type and "referenceName" in node:
                    target = node["referenceName"]
                    if target not in artifacts[by_type[ref_type]]:
                        report.error(f"{kind}/{name}", f"unresolved {ref_type} '{target}'")


def activity_lists(activities: list[dict]) -> Iterator[list[dict]]:
    """Yield every activity container: the top level plus ForEach/If/Until/Switch bodies."""
    yield activities
    for activity in activities:
        props = activity.get("typeProperties", {})
        for key in ("activities", "ifTrueActivities", "ifFalseActivities", "defaultActivities"):
            if isinstance(props.get(key), list):
                yield from activity_lists(props[key])
        for case in props.get("cases", []):
            yield from activity_lists(case.get("activities", []))


def has_cycle(graph: dict[str, list[str]]) -> bool:
    state: dict[str, int] = {}

    def visit(node: str) -> bool:
        if state.get(node) == 1:
            return True
        if state.get(node) == 2:
            return False
        state[node] = 1
        if any(visit(dep) for dep in graph.get(node, [])):
            return True
        state[node] = 2
        return False

    return any(visit(node) for node in graph)


def check_pipelines(artifacts: dict, report: Report) -> None:
    pipelines = artifacts["pipeline"]
    for name, doc in pipelines.items():
        where = f"pipeline/{name}"
        all_names: list[str] = []
        for container in activity_lists(doc["properties"].get("activities", [])):
            names = {a["name"] for a in container}
            all_names.extend(a["name"] for a in container)
            graph = {}
            for activity in container:
                deps = [d["activity"] for d in activity.get("dependsOn", [])]
                graph[activity["name"]] = deps
                for dep in deps:
                    if dep not in names:
                        report.error(where, f"'{activity['name']}' depends on unknown activity '{dep}'")
                if activity.get("type") == "ExecutePipeline":
                    props = activity["typeProperties"]
                    target = pipelines.get(props["pipeline"]["referenceName"])
                    if target:
                        declared = target["properties"].get("parameters", {})
                        for param in props.get("parameters", {}):
                            if param not in declared:
                                report.error(where, f"'{activity['name']}' passes unknown parameter '{param}'")
            if has_cycle(graph):
                report.error(where, "dependency cycle between activities")
        duplicates = {n for n in all_names if all_names.count(n) > 1}
        if duplicates:
            report.error(where, f"duplicate activity names {sorted(duplicates)}")


def check_triggers(artifacts: dict, report: Report) -> None:
    for name, doc in artifacts["trigger"].items():
        for entry in doc["properties"].get("pipelines", []):
            target = artifacts["pipeline"].get(entry["pipelineReference"]["referenceName"])
            if not target:
                continue
            declared = target["properties"].get("parameters", {})
            for param in entry.get("parameters", {}):
                if param not in declared:
                    report.error(f"trigger/{name}", f"unknown pipeline parameter '{param}'")


def check_dataflows(artifacts: dict, report: Report) -> None:
    for name, doc in artifacts["dataflow"].items():
        props = doc["properties"]["typeProperties"]
        script = "\n".join(props.get("scriptLines", []))
        defined = set(re.findall(r"~>\s*(\w+)", script))
        for section in ("sources", "sinks", "transformations"):
            for item in props.get(section, []):
                if item["name"] not in defined:
                    report.error(f"dataflow/{name}", f"{section[:-1]} '{item['name']}' not defined in script")


def check_secrets(artifacts: dict, report: Report) -> None:
    for kind, docs in artifacts.items():
        for name, doc in docs.items():
            for node in walk(doc):
                for key, value in node.items():
                    if key.lower() in SECRET_KEYS and not (
                        isinstance(value, dict) and value.get("type") in {"AzureKeyVaultSecret", "SecureString"}
                    ):
                        report.error(f"{kind}/{name}", f"'{key}' must be a Key Vault secret reference")
                    if isinstance(value, str) and SECRET_PATTERNS.search(value):
                        report.error(f"{kind}/{name}", f"plain-text credential in '{key}'")


def validate(adf_dir: Path) -> Report:
    report = Report()
    artifacts = load_artifacts(adf_dir, report)
    for check in (check_references, check_pipelines, check_triggers, check_dataflows, check_secrets):
        check(artifacts, report)
    return report


def main() -> int:
    adf_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "adf"
    report = validate(adf_dir)
    summary = ", ".join(f"{count} {kind}" for kind, count in report.counts.items())
    print(f"Validated {summary}")
    for error in report.errors:
        print(f"  ERROR {error}")
    print("OK - no problems found" if not report.errors else f"{len(report.errors)} problem(s) found")
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
