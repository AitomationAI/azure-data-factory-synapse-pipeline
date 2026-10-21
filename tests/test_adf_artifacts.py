import copy
import json
import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import validate_adf  # noqa: E402

ADF = ROOT / "adf"


def load(kind, name):
    return json.loads((ADF / kind / f"{name}.json").read_text(encoding="utf-8"))


def activities(pipeline):
    return {a["name"]: a for a in load("pipeline", pipeline)["properties"]["activities"]}


def test_repository_artifacts_are_valid():
    report = validate_adf.validate(ADF)
    assert report.errors == []
    assert report.counts["pipeline"] == 4 and report.counts["dataflow"] == 2


def test_master_pipeline_order():
    acts = activities("pl_master_daily")
    deps = {name: {d["activity"] for d in a.get("dependsOn", [])} for name, a in acts.items()}
    assert deps["ingest_sql_sources"] == deps["ingest_partner_files"] == {"set_load_date"}  # parallel
    assert deps["transform_claims_to_silver"] == {"ingest_sql_sources", "ingest_partner_files"}
    assert deps["load_warehouse"] == {"transform_claims_to_silver", "transform_reference_to_silver"}


def test_failure_alert_also_fires_when_upstream_failed():
    alert = activities("pl_master_daily")["notify_failure"]
    assert alert["dependsOn"][0]["dependencyConditions"] == ["Failed", "Skipped"]
    assert activities("pl_master_daily")["fail_run"]["type"] == "Fail"


def test_incremental_ingest_is_metadata_driven_and_parallel():
    foreach = activities("pl_ingest_sql_incremental")["foreach_source_table"]["typeProperties"]
    assert foreach["isSequential"] is False and foreach["batchCount"] == 4
    inner = {a["name"]: a for a in foreach["activities"]}
    # watermark is only advanced after the copy succeeded
    assert inner["update_watermark"]["dependsOn"][0]["activity"] == "copy_delta_to_bronze"
    query = inner["copy_delta_to_bronze"]["typeProperties"]["source"]["sqlReaderQuery"]["value"]
    assert "> '@{item().watermark_value}'" in query and "<= '@{activity('lkp_new_watermark')" in query


def test_partner_copy_quarantines_bad_rows_instead_of_failing():
    copy_activity = activities("pl_ingest_partner_files")["foreach_file"]["typeProperties"]["activities"][0]
    props = copy_activity["typeProperties"]
    assert props["enableSkipIncompatibleRow"] is True
    assert "quarantine/" in props["logSettings"]["logLocationSettings"]["path"]["value"]


def test_onprem_password_comes_from_key_vault():
    password = load("linkedService", "ls_onprem_sqlserver")["properties"]["typeProperties"]["password"]
    assert password["type"] == "AzureKeyVaultSecret"


# --- the validator itself catches real mistakes ----------------------------------------


@pytest.fixture
def broken(tmp_path):
    target = tmp_path / "adf"
    shutil.copytree(ADF, target)
    return target


def edit(adf, kind, name, mutate):
    path = adf / kind / f"{name}.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    mutate(doc)
    path.write_text(json.dumps(doc), encoding="utf-8")


def test_detects_unresolved_dataset(broken):
    edit(
        broken,
        "pipeline",
        "pl_ingest_partner_files",
        lambda d: d["properties"]["activities"][0]["typeProperties"]["dataset"].update(referenceName="ds_missing"),
    )
    assert any("unresolved DatasetReference 'ds_missing'" in e for e in validate_adf.validate(broken).errors)


def test_detects_unknown_dependency_and_cycle(broken):
    def mutate(doc):
        acts = doc["properties"]["activities"]
        acts[0]["dependsOn"] = [{"activity": acts[1]["name"], "dependencyConditions": ["Succeeded"]}]
        acts[2]["dependsOn"] = [{"activity": "ghost", "dependencyConditions": ["Succeeded"]}]

    edit(broken, "pipeline", "pl_master_daily", mutate)
    errors = validate_adf.validate(broken).errors
    assert any("unknown activity 'ghost'" in e for e in errors)
    assert any("dependency cycle" in e for e in errors)


def test_detects_plain_text_password(broken):
    edit(
        broken,
        "linkedService",
        "ls_onprem_sqlserver",
        lambda d: d["properties"]["typeProperties"].update(password="hunter2"),
    )
    assert any("Key Vault secret" in e for e in validate_adf.validate(broken).errors)


def test_detects_unknown_pipeline_parameter(broken):
    def mutate(doc):
        doc["properties"]["activities"][1]["typeProperties"]["parameters"] = copy.deepcopy(
            {"loadDate": "x", "notAParam": "y"}
        )

    edit(broken, "pipeline", "pl_master_daily", mutate)
    assert any("unknown parameter 'notAParam'" in e for e in validate_adf.validate(broken).errors)
