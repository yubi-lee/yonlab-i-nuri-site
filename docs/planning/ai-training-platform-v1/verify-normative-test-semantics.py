#!/usr/bin/env python3
"""Fail closed when a test ID is detached from its normative meaning."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


NORMATIVE_MAP_SHA256 = "dc2310b7420b5152889f6d5c79f2920dcb9b2263816b9e9d4db063ba966799da"
REGISTRY_CASE_AGGREGATE_SHA256 = "696ba7a95b2b19bee5203f42c1d01bc26f4f3123834b99b509525bc95a422d77"
REGISTRY_CATALOG_AGGREGATE_SHA256 = "351925e977b1de8887e57fcdbbbb51d7e2a6cbe241429fbdfe5f25931127f95d"


def canonical(value: Any) -> str:
    def reject(node: Any) -> None:
        if isinstance(node, float):
            raise ValueError("float is outside the integer/string canonical subset")
        if isinstance(node, dict):
            if not all(isinstance(key, str) for key in node):
                raise ValueError("object keys must be strings")
            for child in node.values():
                reject(child)
        elif isinstance(node, list):
            for child in node:
                reject(child)
        elif node is not None and not isinstance(node, (str, int, bool)):
            raise ValueError(f"unsupported canonical value: {type(node).__name__}")

    reject(value)
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


class Verification:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def require(self, condition: bool, message: str) -> None:
        if not condition:
            self.failures.append(message)

    def finish(self) -> int:
        if self.failures:
            for message in self.failures:
                print(f"FAIL [NORMATIVE_TEST_SEMANTICS]: {message}")
            print("RESULT: FAIL")
            return 1
        print("PASS [NORMATIVE_TEST_SEMANTICS]: 139 IDs preserve exact normative anchors, metrics, formulas, and registry oracles")
        print("RESULT: PASS")
        return 0


def load(path: Path, verification: Verification) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        verification.require(False, f"cannot load {path.name}: {exc}")
        return {}


def scaled_ratio(baseline: dict[str, Any], kpi_id: str, field: str) -> int | None:
    row = next((item for item in baseline.get("kpis", []) if item.get("id") == kpi_id), None)
    if not isinstance(row, dict) or not isinstance(row.get(field), (int, float)):
        return None
    return round(row[field] * 1_000_000)


def verify(package_root: Path) -> int:
    result = Verification()
    map_path = package_root / "normative-test-semantics.json"
    registry_path = package_root / "requirements-test-registry.json"
    procedure_path = package_root / "09-test-procedure-acceptance.md"
    baseline_path = package_root / "design-baseline.json"
    matrix_path = package_root / "kpi-005-structured-output-matrix.json"

    try:
        map_digest = hashlib.sha256(map_path.read_bytes()).hexdigest()
    except OSError as exc:
        result.require(False, f"cannot read normative map: {exc}")
        map_digest = ""
    result.require(map_digest == NORMATIVE_MAP_SHA256, "normative map digest drift; ID-to-meaning changes require explicit checker review")

    semantic_map = load(map_path, result)
    registry = load(registry_path, result)
    baseline = load(baseline_path, result)
    matrix = load(matrix_path, result)
    try:
        procedure_text = procedure_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        result.require(False, f"cannot read procedure document: {exc}")
        procedure_text = ""

    result.require(
        isinstance(semantic_map, dict)
        and set(semantic_map)
        == {"schema_version", "document_id", "normative_source", "cardinality", "canonicalization", "ratio_scale", "tests"}
        and semantic_map.get("schema_version") == "normative-test-semantics.v1"
        and semantic_map.get("document_id") == "VER-ATP-009-SEMANTICS"
        and semantic_map.get("normative_source") == procedure_path.name
        and semantic_map.get("cardinality") == 139
        and semantic_map.get("canonicalization") == "RFC8785-compatible integer/string subset"
        and semantic_map.get("ratio_scale") == {"unit": "microunit_ratio", "one": 1_000_000},
        "normative map header contract drift",
    )

    rows = semantic_map.get("tests", []) if isinstance(semantic_map, dict) else []
    tests = registry.get("tests", []) if isinstance(registry, dict) else []
    expected_row_keys = {
        "test_id",
        "title",
        "normative_anchor",
        "requirement_ids",
        "procedure_id",
        "metric_id",
        "acceptance_formula",
        "comparator",
        "threshold",
        "expected_error",
        "fixture_contract_id",
        "command_contract_id",
        "authorization_case_ids",
    }
    result.require(isinstance(rows, list) and len(rows) == 139, "normative map must contain exactly 139 rows")
    result.require(isinstance(tests, list) and len(tests) == 139, "registry must contain exactly 139 tests")
    map_ids = [row.get("test_id") for row in rows if isinstance(row, dict)]
    registry_ids = [row.get("test_id") for row in tests if isinstance(row, dict)]
    result.require(map_ids == registry_ids and len(set(map_ids)) == 139, "map IDs must exactly preserve registry order and uniqueness")
    by_test = {test.get("test_id"): test for test in tests if isinstance(test, dict)}

    generic_fragments = {
        "등록 입력과 정책 경계",
        "정상 상태와 감사 증거",
        "실패 주입과 fail-closed",
        "재실행 결정성",
        "권한·tenant 역추적",
        "schema 거부 경로",
        "artifact hash 결속",
        "복구 후 상태 일치",
    }
    metric_ids: list[str] = []
    formulas: list[str] = []
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            result.require(False, "normative semantic row must be an object")
            continue
        test_id = row.get("test_id", "<missing>")
        test = by_test.get(test_id, {})
        result.require(set(row) == expected_row_keys, f"{test_id} normative row key contract drift")
        result.require(row.get("normative_anchor") == f"VER-ATP-009#{test_id}", f"{test_id} normative anchor drift")
        result.require(
            re.search(rf"^\|\s*{re.escape(str(test_id))}\s*\|", procedure_text, re.MULTILINE) is not None,
            f"{test_id} has no explicit table row in 09-test-procedure-acceptance.md",
        )
        title = row.get("title")
        result.require(isinstance(title, str) and str(test_id) in title and not any(fragment in title for fragment in generic_fragments), f"{test_id} title is generic or detached")
        metric_id = row.get("metric_id")
        formula = row.get("acceptance_formula")
        result.require(isinstance(metric_id, str) and re.fullmatch(r"METRIC-[A-Z0-9-]+", metric_id) is not None, f"{test_id} metric_id invalid")
        result.require(isinstance(formula, str) and len(formula) >= 20 and any(token in formula for token in (" == ", " >= ", " <= ", " < ")), f"{test_id} acceptance formula is not executable")
        if isinstance(metric_id, str):
            metric_ids.append(metric_id)
        if isinstance(formula, str):
            formulas.append(formula)
        threshold = row.get("threshold", {})
        result.require(
            isinstance(threshold, dict)
            and set(threshold) == {"metric", "comparison", "value", "unit"}
            and isinstance(threshold.get("metric"), str)
            and threshold.get("comparison") in {"<=", "==", ">="}
            and isinstance(threshold.get("value"), int)
            and not isinstance(threshold.get("value"), bool)
            and isinstance(threshold.get("unit"), str),
            f"{test_id} threshold must use the canonical integer contract",
        )
        if isinstance(threshold, dict) and isinstance(formula, str):
            result.require(str(threshold.get("metric")) in formula, f"{test_id} primary threshold metric is absent from acceptance formula")
        result.require(row.get("title") == test.get("title"), f"{test_id} registry title differs from normative title")
        result.require(row.get("requirement_ids") == test.get("requirement_ids"), f"{test_id} requirement binding drift")
        result.require(row.get("procedure_id") == test.get("procedure_id"), f"{test_id} procedure binding drift")
        result.require(row.get("comparator") == test.get("comparator"), f"{test_id} comparator binding drift")
        result.require(row.get("threshold") == test.get("threshold"), f"{test_id} threshold binding drift")
        result.require(row.get("expected_error") == test.get("expected_error"), f"{test_id} expected error binding drift")
        result.require(row.get("fixture_contract_id") == test.get("dataset_contract_id"), f"{test_id} fixture contract binding drift")
        result.require(row.get("command_contract_id") == test.get("command_contract_id"), f"{test_id} command contract binding drift")
        authorization_case_ids = row.get("authorization_case_ids")
        result.require(
            isinstance(authorization_case_ids, list)
            and all(isinstance(case_id, str) and re.fullmatch(r"AUTHZ-[A-Z0-9-]+", case_id) for case_id in authorization_case_ids)
            and len(authorization_case_ids) == len(set(authorization_case_ids)),
            f"{test_id} authorization case links invalid",
        )
        is_negative = row.get("expected_error") != "NONE"
        input_contract = test.get("input", {}) if isinstance(test, dict) else {}
        parameters = input_contract.get("parameters", {}) if isinstance(input_contract, dict) else {}
        result.require(input_contract.get("dataset_partition") == ("synthetic-negative" if is_negative else "synthetic-positive"), f"{test_id} dataset partition does not match controlled error path")
        result.require(parameters.get("negative_path") is is_negative, f"{test_id} negative_path does not match controlled error path")

    result.require(len(metric_ids) == len(set(metric_ids)) == 139, "metric IDs must be unique so ID swaps cannot alias")
    result.require(len(formulas) == len(set(formulas)) == 139, "acceptance formulas must be unique so cyclic templates cannot alias")

    # Normative KPI and matrix bindings cited by the acceptance procedure.
    map_by_id = {row.get("test_id"): row for row in rows if isinstance(row, dict)}
    expected_kpi_thresholds = {
        "T-AI-004": scaled_ratio(baseline, "KPI-001", "minimum"),
        "T-REC-002": scaled_ratio(baseline, "KPI-002", "minimum"),
        "T-DOC-008": scaled_ratio(baseline, "KPI-003", "minimum"),
        "T-DOC-009": scaled_ratio(baseline, "KPI-004", "minimum"),
        "T-KPI-005": scaled_ratio(baseline, "KPI-005", "minimum"),
        "T-PILOT-006": scaled_ratio(baseline, "KPI-007", "minimum"),
    }
    for test_id, expected in expected_kpi_thresholds.items():
        actual = map_by_id.get(test_id, {}).get("threshold", {}).get("value")
        result.require(expected is not None and actual == expected, f"{test_id} threshold is detached from design-baseline KPI")
    result.require(map_by_id.get("T-PRIV-004", {}).get("threshold", {}).get("value") == 0, "T-PRIV-004 must implement KPI-008 zero restricted egress")
    for test_id in (f"T-A11Y-{index:03d}" for index in range(1, 9)):
        result.require(map_by_id.get(test_id, {}).get("threshold", {}).get("value") == 0, f"{test_id} must implement KPI-009 zero accessibility violations")
    doc9_formula = str(map_by_id.get("T-DOC-009", {}).get("acceptance_formula", ""))
    result.require("invalid_citation_count == 0" in doc9_formula, "T-DOC-009 must bind citation coverage and zero invalid citations")
    docs2 = map_by_id.get("T-DOCS-002", {})
    result.require(
        docs2.get("acceptance_formula")
        == "final_document_contract_error_count == 0 AND inventory_item_count == 147 AND markdown_pdf_pair_count == 8"
        and "147-item inventory" in str(docs2.get("title", "")),
        "T-DOCS-002 must bind the exact 147-item final inventory",
    )

    result.require(matrix.get("required_case_count") == 27 and len(matrix.get("coverage_cells", [])) == 27, "KPI-005 must contain 27 explicit cells")
    result.require(matrix.get("sample_policy", {}).get("minimum_requests_per_task_provider_path") == 1000, "KPI-005 cell denominator floor drift")
    result.require(matrix.get("sample_policy", {}).get("minimum_total_requests") == 27000, "KPI-005 total denominator floor drift")
    result.require(round(matrix.get("acceptance", {}).get("overall_minimum", 0) * 1_000_000) == map_by_id.get("T-KPI-005", {}).get("threshold", {}).get("value"), "KPI-005 overall threshold drift")
    result.require(round(matrix.get("acceptance", {}).get("per_task_provider_path_minimum", 0) * 1_000_000) == 995_000, "KPI-005 per-cell threshold drift")
    kpi5_formula = str(map_by_id.get("T-KPI-005", {}).get("acceptance_formula", ""))
    for clause in ("minimum_cell_success_microunit >= 995000", "executed_cell_count == 27", "minimum_cell_denominator >= 1000", "total_denominator >= 27000", "second_repair_count == 0", "unknown_schema_count == 0"):
        result.require(clause in kpi5_formula, f"T-KPI-005 acceptance formula missing: {clause}")

    # Registry projections must be self-consistent and independently pinned.
    case_rows: list[dict[str, Any]] = []
    expected_catalog: list[dict[str, Any]] = []
    for test in tests if isinstance(tests, list) else []:
        if not isinstance(test, dict):
            continue
        projection = {key: value for key, value in test.items() if key != "semantic_case_sha256"}
        case_rows.append(projection)
        try:
            digest = hashlib.sha256(canonical(projection).encode("utf-8")).hexdigest()
            parameters_digest = hashlib.sha256(canonical(test["input"]["parameters"]).encode("utf-8")).hexdigest()
        except (ValueError, KeyError, TypeError) as exc:
            result.require(False, f"{test.get('test_id')} canonical projection invalid: {exc}")
            continue
        result.require(test.get("semantic_case_sha256") == digest, f"{test.get('test_id')} semantic case digest mismatch")
        expected_catalog.append(
            {
                "test_id": test.get("test_id"),
                "dataset_contract_id": test.get("dataset_contract_id"),
                "fixture_id": test.get("fixture_id"),
                "fixture_path": test.get("fixture_path"),
                "dataset_partition": test.get("input", {}).get("dataset_partition"),
                "parameters_sha256": parameters_digest,
                "oracle_id": test.get("oracle_id"),
                "observation_path": f"$.metrics.{test.get('threshold', {}).get('metric')}",
                "comparator": test.get("comparator"),
                "comparison": test.get("threshold", {}).get("comparison"),
                "expected_value": test.get("threshold", {}).get("value"),
                "unit": test.get("threshold", {}).get("unit"),
                "expected_error": test.get("expected_error"),
                "command_contract_id": test.get("command_contract_id"),
            }
        )
    try:
        case_aggregate = hashlib.sha256(canonical(case_rows).encode("utf-8")).hexdigest()
        catalog_aggregate = hashlib.sha256(canonical(expected_catalog).encode("utf-8")).hexdigest()
    except ValueError as exc:
        result.require(False, f"registry aggregate cannot be canonicalized: {exc}")
        case_aggregate = catalog_aggregate = ""
    contract = registry.get("semantic_case_contract", {}) if isinstance(registry, dict) else {}
    result.require(case_aggregate == contract.get("aggregate_sha256") == REGISTRY_CASE_AGGREGATE_SHA256, "registry 139-case aggregate drift")
    result.require(catalog_aggregate == contract.get("catalog_aggregate_sha256") == REGISTRY_CATALOG_AGGREGATE_SHA256, "registry 139-oracle catalog aggregate drift")
    result.require(registry.get("test_semantic_catalog") == expected_catalog, "registry oracle catalog is not derived from exact tests")

    return result.finish()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-root", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    return verify(args.package_root.resolve())


if __name__ == "__main__":
    sys.exit(main())
