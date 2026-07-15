#!/usr/bin/env python3
"""Fail-closed semantic verifier for YOnLab machine-readable design contracts.

The verifier intentionally depends only on the Python standard library so the
Bash and PowerShell package gates can invoke the same implementation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import unicodedata
import uuid
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


FINAL_DOCUMENT_INVENTORY_SHA256 = "a04cab366c41774b76b7ee3e3060b590f160659d01079ffcb9f7e172e8d1a8a4"
TEST_SEMANTIC_AGGREGATE_SHA256 = "696ba7a95b2b19bee5203f42c1d01bc26f4f3123834b99b509525bc95a422d77"
TEST_SEMANTIC_CATALOG_SHA256 = "351925e977b1de8887e57fcdbbbb51d7e2a6cbe241429fbdfe5f25931127f95d"
SCREEN_OPERATION_AGGREGATE_SHA256 = "cc9be193778d07e64c64786526506b2efa0900f845aecbe7b0e2b673811e47ff"
HWP_BOUNDARY_CONTRACT_SHA256 = "0fd0a189966cbef24fb58bfac7860e40b574b763a189d4cb5e65a3995bdce145"
NORMATIVE_TEST_SEMANTICS_SHA256 = "4469747a71f20a4f4b686df2db3fe20e6979e7f988e81bd6cdbb7d67e442be4f"
TCH015_AUTHORIZATION_SHA256 = "a569faacf5ea18cbf9938c0e954fb70eb49cf050d90f0cdb98651f2fe328a081"
SAFEGUARDING_VECTORS_SHA256 = "079b97792a8aebba19134c48b69af88645b44d7ed8be69e916540375e7d4f070"

SCREEN_ROLE_VOCABULARY = [
    "ANONYMOUS",
    "AUTHENTICATED",
    "CONTENT_ADMIN",
    "CONTENT_REVIEWER",
    "EXPERT_REVIEWER",
    "INSTITUTION_ADMIN",
    "OPERATIONS_OPERATOR",
    "SECURITY_AUDITOR",
    "SYSTEM_ADMIN",
    "TEACHER",
]

TENANT_GUARD_VOCABULARY = [
    "ACTIVE_TENANT_CURRENT_RIGHTS",
    "ACTIVE_TENANT_MEMBERSHIP",
    "ACTIVE_TENANT_OWNERSHIP",
    "ACTIVE_TENANT_ROLE_MFA",
    "ACTIVE_TENANT_ROLE_MFA_REAUTH",
    "NO_TENANT_PREAUTH",
    "PUBLIC_OR_ACTIVE_TENANT_RIGHTS",
    "PUBLIC_REGISTRY_READ",
]


class Report:
    def __init__(self) -> None:
        self.failures: list[tuple[str, str]] = []
        self.passes: list[tuple[str, str]] = []

    def require(self, condition: bool, code: str, message: str) -> None:
        if not condition:
            self.failures.append((code, message))

    def pass_group(self, code: str, message: str, failure_count: int) -> None:
        if len(self.failures) == failure_count:
            self.passes.append((code, message))

    def finish(self) -> int:
        for code, message in self.passes:
            print(f"PASS [{code}]: {message}")
        for code, message in self.failures:
            print(f"FAIL [{code}]: {message}")
        result = "FAIL" if self.failures else "PASS"
        print(f"RESULT: {result}")
        return 1 if self.failures else 0


def load_json(path: Path, report: Report) -> Any | None:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        report.require(False, "JSON_PARSE", f"missing JSON file: {path.name}")
    except UnicodeDecodeError as exc:
        report.require(False, "JSON_PARSE", f"non-UTF-8 JSON file {path.name}: {exc}")
    except json.JSONDecodeError as exc:
        report.require(False, "JSON_PARSE", f"invalid JSON {path.name}:{exc.lineno}:{exc.colno}: {exc.msg}")
    return None


def is_nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def is_nonempty_unique_strings(value: Any) -> bool:
    return (
        isinstance(value, list)
        and bool(value)
        and all(is_nonempty_string(item) for item in value)
        and len(value) == len(set(value))
    )


def canonical_json(value: Any) -> str:
    """RFC 8785-compatible serialization for the integer/string contract subset."""

    def reject_non_subset(node: Any) -> None:
        if isinstance(node, float):
            raise ValueError("floating-point numbers are outside the source-tree JCS subset")
        if isinstance(node, dict):
            for key, child in node.items():
                if not isinstance(key, str):
                    raise ValueError("JCS object key must be a string")
                reject_non_subset(child)
        elif isinstance(node, list):
            for child in node:
                reject_non_subset(child)
        elif node is not None and not isinstance(node, (str, int, bool)):
            raise ValueError(f"unsupported JCS value: {type(node).__name__}")

    reject_non_subset(value)
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def fixed_int(value: Any, digits: int) -> int:
    if not isinstance(value, str) or re.fullmatch(rf"(?:0|[1-9][0-9]*)\.[0-9]{{{digits}}}", value) is None:
        raise ValueError(f"not a canonical fixed-{digits} decimal: {value!r}")
    whole, fraction = value.split(".", 1)
    return int(whole) * (10**digits) + int(fraction)


def fixed_string(value: int, digits: int) -> str:
    scale = 10**digits
    return f"{value // scale}.{value % scale:0{digits}d}"


def div_half_up(numerator: int, denominator: int) -> int:
    if numerator < 0 or denominator <= 0:
        raise ValueError("div_half_up requires numerator >= 0 and denominator > 0")
    return (2 * numerator + denominator) // (2 * denominator)


def verify_pinned_semantic_contracts(package_root: Path, report: Report) -> None:
    before = len(report.failures)
    code = "PINNED_SEMANTICS"
    expected = {
        "normative-test-semantics.json": NORMATIVE_TEST_SEMANTICS_SHA256,
        "tch-015-authorization-contract.json": TCH015_AUTHORIZATION_SHA256,
        "fixtures/ai-gateway-safeguarding-decision-vectors.json": SAFEGUARDING_VECTORS_SHA256,
    }
    for relative_path, expected_digest in expected.items():
        contract = load_json(package_root / relative_path, report)
        if not isinstance(contract, dict):
            report.require(False, code, f"{relative_path} root must be an object")
            continue
        try:
            digest = hashlib.sha256(canonical_json(contract).encode("utf-8")).hexdigest()
        except ValueError as exc:
            report.require(False, code, f"{relative_path} is outside the canonical subset: {exc}")
            continue
        report.require(digest == expected_digest, code, f"{relative_path} canonical semantic digest drift")
    report.pass_group(code, "normative formulas, TCH-015 ABAC, and safeguarding route vectors are digest-pinned", before)


def verify_registry(
    registry: dict[str, Any],
    screens: dict[str, Any],
    baseline: dict[str, Any],
    package_root: Path,
    report: Report,
) -> None:
    before = len(report.failures)
    code = "REGISTRY"
    report.require(registry.get("schema_version") == "requirements-test-registry.v1", code, "schema_version drift")
    rfp = registry.get("rfp_requirements", [])
    system = registry.get("system_requirements", [])
    tests = registry.get("tests", [])
    procedures = registry.get("procedure_catalog", [])
    report.require(
        registry.get("cardinality_contract") == {"rfp_requirements": 60, "system_requirements": 33, "minimum_tests": 1, "exact_tests": 139},
        code,
        "registry cardinality contract drift",
    )
    report.require(all(isinstance(items, list) for items in (rfp, system, tests, procedures)), code, "registry inventories must be arrays")
    if not all(isinstance(items, list) for items in (rfp, system, tests, procedures)):
        return

    normative_semantics = load_json(package_root / "normative-test-semantics.json", report)
    normative_rows = normative_semantics.get("tests", []) if isinstance(normative_semantics, dict) else []
    normative_by_test = {
        row.get("test_id"): row
        for row in normative_rows
        if isinstance(row, dict) and is_nonempty_string(row.get("test_id"))
    }
    report.require(
        isinstance(normative_semantics, dict)
        and normative_semantics.get("schema_version") == "normative-test-semantics.v1"
        and normative_semantics.get("cardinality") == 139
        and [row.get("test_id") for row in normative_rows if isinstance(row, dict)]
        == [row.get("test_id") for row in tests if isinstance(row, dict)]
        and len(normative_by_test) == 139,
        code,
        "normative 139-test semantic map identity/order drift",
    )

    expected_rfp_counts = {
        "PLR": 4,
        "ECR": 2,
        "DER": 8,
        "SIR": 3,
        "DAR": 7,
        "TER": 4,
        "SER": 8,
        "QUR": 5,
        "COR": 6,
        "PMR": 8,
        "PSR": 5,
    }
    expected_rfp_ids = [
        f"{prefix}-{number:03d}"
        for prefix, count in expected_rfp_counts.items()
        for number in range(1, count + 1)
    ]
    expected_system_ids = [f"SYS-F-{number:03d}" for number in range(1, 19)] + [
        f"SYS-NF-{number:03d}" for number in range(1, 16)
    ]
    rfp_ids = [item.get("requirement_id") for item in rfp if isinstance(item, dict)]
    system_ids = [item.get("requirement_id") for item in system if isinstance(item, dict)]
    test_ids = [item.get("test_id") for item in tests if isinstance(item, dict)]
    procedure_ids = [item.get("procedure_id") for item in procedures if isinstance(item, dict)]
    report.require(rfp_ids == expected_rfp_ids, code, "RFP IDs must be the exact ordered 60-row inventory")
    report.require(system_ids == expected_system_ids, code, "system IDs must be SYS-F-001..018 then SYS-NF-001..015")
    report.require(len(test_ids) == 139 and len(set(test_ids)) == 139, code, "tests must contain exactly 139 unique IDs")
    report.require(len(procedure_ids) == 28 and len(set(procedure_ids)) == 28, code, "procedure catalog must contain exactly 28 unique IDs")
    report.require(not any(re.search(r"[~～…]", str(item)) for item in test_ids), code, "unexpanded test range token found")

    semantic_contract = registry.get("semantic_case_contract", {})
    report.require(
        semantic_contract
        == {
            "hash_algorithm": "SHA-256",
            "canonicalization": "RFC8785-compatible integer/string subset",
            "case_projection": "Each ordered tests[] object with semantic_case_sha256 omitted",
            "oracle_fields": ["comparator", "threshold", "expected_error"],
            "fixture_fields": ["fixture_id", "input"],
            "command_field": "command",
            "catalog_reference_fields": ["dataset_contract_id", "fixture_path", "oracle_id", "command_contract_id"],
            "aggregate_projection": "Ordered array of every case projection",
            "aggregate_sha256": TEST_SEMANTIC_AGGREGATE_SHA256,
            "catalog_aggregate_sha256": TEST_SEMANTIC_CATALOG_SHA256,
        },
        code,
        "test semantic case/oracle/fixture/command aggregate contract drift",
    )

    all_requirements = [*rfp, *system]
    requirement_by_id = {
        item.get("requirement_id"): item
        for item in all_requirements
        if isinstance(item, dict) and is_nonempty_string(item.get("requirement_id"))
    }
    test_by_id = {
        item.get("test_id"): item
        for item in tests
        if isinstance(item, dict) and is_nonempty_string(item.get("test_id"))
    }
    procedure_by_id = {
        item.get("procedure_id"): item
        for item in procedures
        if isinstance(item, dict) and is_nonempty_string(item.get("procedure_id"))
    }
    screen_ids = {
        item.get("screen_id")
        for item in screens.get("screens", [])
        if isinstance(item, dict) and is_nonempty_string(item.get("screen_id"))
    }
    gate_ids = {
        item.get("id")
        for item in baseline.get("release_gates", [])
        if isinstance(item, dict) and is_nonempty_string(item.get("id"))
    }

    markdown = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(package_root.glob("*.md"))
        if path.is_file()
    )
    for requirement in all_requirements:
        if not isinstance(requirement, dict):
            report.require(False, code, "requirement row must be an object")
            continue
        requirement_id = requirement.get("requirement_id", "<missing>")
        for field in ("design_ids", "test_ids", "evidence_ids", "gate_ids", "owner_ids", "data_entity_ids", "code_targets"):
            report.require(is_nonempty_unique_strings(requirement.get(field)), code, f"{requirement_id}.{field} must be nonempty and unique")
        for field in ("screen_ids", "api_operation_ids"):
            value = requirement.get(field)
            report.require(isinstance(value, list) and all(is_nonempty_string(item) for item in value) and len(value) == len(set(value)), code, f"{requirement_id}.{field} must be a unique string array")
        for design_id in requirement.get("design_ids", []):
            report.require(design_id in markdown, code, f"{requirement_id} design reference is absent from Markdown: {design_id}")
        for screen_id in requirement.get("screen_ids", []):
            report.require(screen_id in screen_ids, code, f"{requirement_id} references unknown screen: {screen_id}")
        for gate_id in requirement.get("gate_ids", []):
            report.require(gate_id in gate_ids, code, f"{requirement_id} references unknown gate: {gate_id}")
        linked_evidence: list[str] = []
        for test_id in requirement.get("test_ids", []):
            test = test_by_id.get(test_id)
            report.require(test is not None, code, f"{requirement_id} references unknown test: {test_id}")
            if test is not None:
                report.require(requirement_id in test.get("requirement_ids", []), code, f"missing reverse edge {test_id} -> {requirement_id}")
                linked_evidence.append(test.get("evidence_id"))
        report.require(set(requirement.get("evidence_ids", [])) == set(linked_evidence), code, f"{requirement_id} evidence_ids must equal linked test evidence")

    evidence_ids: list[str] = []
    reference_contract = registry.get("procedure_reference_contract", {})
    report.require(reference_contract.get("precondition_id_template") == "{procedure_id}-PRE", code, "procedure precondition template drift")
    report.require(reference_contract.get("action_id_template") == "{procedure_id}-ACT-{one_based_step_2digit}", code, "procedure action template drift")
    report.require(reference_contract.get("expected_result_id_template") == "{procedure_id}-EXPECTED", code, "procedure expected template drift")
    report.require(is_nonempty_string(reference_contract.get("resolution_rule")) and is_nonempty_string(reference_contract.get("orphan_rule")), code, "procedure resolution/orphan rule is missing")

    concrete_contract = registry.get("concrete_test_contract", {})
    concrete_fields = ["fixture_id", "input", "command", "comparator", "threshold", "expected_error", "evidence"]
    allowed_comparators = ["ACCESSIBILITY_ZERO_VIOLATION", "EXACT_JSON", "NUMERIC_THRESHOLD", "SCHEMA_AND_POLICY", "STATE_AND_AUDIT"]
    report.require(
        concrete_contract.get("required_fields") == concrete_fields
        and concrete_contract.get("command_prefix") == ["python", "-m", "tests.contract_runner"]
        and concrete_contract.get("allowed_comparators") == allowed_comparators
        and concrete_contract.get("none_error_literal") == "NONE",
        code,
        "concrete parameterized test contract drift",
    )
    generic_title_pattern = concrete_contract.get("generic_title_forbidden_pattern")
    try:
        generic_title_regex = re.compile(generic_title_pattern) if is_nonempty_string(generic_title_pattern) else None
    except re.error:
        generic_title_regex = None
    report.require(generic_title_regex is not None, code, "generic-title rejection pattern is invalid")
    report.require(
        registry.get("command_contract_catalog")
        == [
            {
                "command_contract_id": "CMD-CONTRACT-RUNNER-V1",
                "working_directory": "REPOSITORY_ROOT",
                "argv_template": ["python", "-m", "tests.contract_runner", "--case", "{test_id}", "--fixture", "{fixture_id}"],
                "exit_code_policy": "ZERO_ONLY",
                "stdout_contract": "ONE_JSON_OBJECT_MATCHING_TEST_EVIDENCE_SCHEMA",
                "stderr_contract": "NO_SECRET_OR_PERSONAL_DATA",
            }
        ],
        code,
        "canonical contract-runner command catalog drift",
    )
    semantic_catalog = registry.get("test_semantic_catalog", [])
    report.require(
        isinstance(semantic_catalog, list)
        and len(semantic_catalog) == 139
        and len({row.get("test_id") for row in semantic_catalog if isinstance(row, dict)}) == 139,
        code,
        "test semantic dataset/oracle catalog must contain 139 unique rows",
    )
    semantic_catalog_by_test = {
        row.get("test_id"): row
        for row in semantic_catalog
        if isinstance(row, dict) and is_nonempty_string(row.get("test_id"))
    }

    for procedure in procedures:
        if not isinstance(procedure, dict):
            report.require(False, code, "procedure row must be an object")
            continue
        procedure_id = procedure.get("procedure_id", "<missing>")
        report.require(is_nonempty_unique_strings(procedure.get("owner_ids")), code, f"{procedure_id}.owner_ids missing")
        report.require(is_nonempty_string(procedure.get("level")), code, f"{procedure_id}.level missing")
        report.require(is_nonempty_unique_strings(procedure.get("preconditions")), code, f"{procedure_id}.preconditions missing")
        report.require(is_nonempty_unique_strings(procedure.get("actions")), code, f"{procedure_id}.actions missing")
        report.require(is_nonempty_string(procedure.get("expected")), code, f"{procedure_id}.expected missing")
        report.require(is_nonempty_unique_strings(procedure.get("evidence_fields")), code, f"{procedure_id}.evidence_fields missing")
        report.require(
            set(procedure)
            == {
                "procedure_id", "owner_ids", "level", "preconditions", "actions", "expected", "evidence_fields",
                "fixture_family", "command_template", "comparator_family", "threshold_source", "expected_error_policy",
            },
            code,
            f"{procedure_id} key contract drift",
        )
        report.require(procedure.get("fixture_family") == f"FIXTURE-FAMILY-{str(procedure_id).removeprefix('PROC-')}", code, f"{procedure_id} fixture family drift")
        report.require(procedure.get("command_template") == ["python", "-m", "tests.contract_runner", "--case", "{test_id}", "--fixture", "{fixture_id}"], code, f"{procedure_id} command template drift")
        report.require(is_nonempty_unique_strings(procedure.get("comparator_family")) and set(procedure.get("comparator_family", [])) <= set(allowed_comparators), code, f"{procedure_id} comparator family invalid")
        report.require(procedure.get("threshold_source") == "tests[].threshold" and is_nonempty_string(procedure.get("expected_error_policy")), code, f"{procedure_id} parameter source/error policy drift")

    report.require(len({tuple(item.get("preconditions", [])) for item in procedures if isinstance(item, dict)}) == 28, code, "28 procedures must have distinct precondition contracts")
    report.require(len({tuple(item.get("actions", [])) for item in procedures if isinstance(item, dict)}) == 28, code, "28 procedures must have distinct action contracts")
    report.require(len({item.get("expected") for item in procedures if isinstance(item, dict)}) == 28, code, "28 procedures must have distinct expected-result contracts")

    for test in tests:
        if not isinstance(test, dict):
            report.require(False, code, "test row must be an object")
            continue
        test_id = test.get("test_id", "<missing>")
        report.require(
            set(test)
            == {
                "test_id", "title", "requirement_ids", "procedure_id", "evidence_id", "gate_ids", "owner_ids",
                "precondition_ids", "action_ids", "expected_result_id", *concrete_fields,
                "semantic_case_sha256",
                "dataset_contract_id", "fixture_path", "oracle_id", "command_contract_id",
            },
            code,
            f"{test_id} key contract drift",
        )
        title = test.get("title")
        report.require(is_nonempty_string(title) and test_id in title and (generic_title_regex is None or generic_title_regex.search(title) is None), code, f"{test_id} title is generic or does not identify its case")
        requirement_ids = test.get("requirement_ids", [])
        report.require(is_nonempty_unique_strings(requirement_ids), code, f"{test_id}.requirement_ids missing")
        report.require(is_nonempty_unique_strings(test.get("gate_ids")), code, f"{test_id}.gate_ids missing")
        report.require(is_nonempty_unique_strings(test.get("owner_ids")), code, f"{test_id}.owner_ids missing")
        for requirement_id in requirement_ids:
            requirement = requirement_by_id.get(requirement_id)
            report.require(requirement is not None, code, f"{test_id} references unknown requirement: {requirement_id}")
            if requirement is not None:
                report.require(test_id in requirement.get("test_ids", []), code, f"missing reverse edge {requirement_id} -> {test_id}")
        procedure_id = test.get("procedure_id")
        procedure = procedure_by_id.get(procedure_id)
        report.require(procedure is not None, code, f"{test_id} references unknown procedure: {procedure_id}")
        if procedure is not None:
            expected_actions = [f"{procedure_id}-ACT-{index:02d}" for index in range(1, len(procedure.get("actions", [])) + 1)]
            report.require(test.get("precondition_ids") == [f"{procedure_id}-PRE"], code, f"{test_id} precondition reference does not resolve")
            report.require(test.get("action_ids") == expected_actions, code, f"{test_id} action references do not resolve in order")
            report.require(test.get("expected_result_id") == f"{procedure_id}-EXPECTED", code, f"{test_id} expected-result reference does not resolve")
        evidence_id = test.get("evidence_id")
        report.require(is_nonempty_string(evidence_id), code, f"{test_id}.evidence_id missing")
        if is_nonempty_string(evidence_id):
            evidence_ids.append(evidence_id)
        for gate_id in test.get("gate_ids", []):
            report.require(gate_id in gate_ids, code, f"{test_id} references unknown gate: {gate_id}")
        fixture_id = test.get("fixture_id")
        report.require(fixture_id == f"FIX-{str(test_id).removeprefix('T-')}", code, f"{test_id} fixture ID drift")
        input_contract = test.get("input", {})
        report.require(
            isinstance(input_contract, dict)
            and set(input_contract) == {"fixture_id", "dataset_partition", "parameters"}
            and input_contract.get("fixture_id") == fixture_id
            and input_contract.get("dataset_partition") in {"synthetic-positive", "synthetic-negative"}
            and isinstance(input_contract.get("parameters"), dict)
            and input_contract["parameters"].get("case_id") == test_id
            and isinstance(input_contract["parameters"].get("negative_path"), bool)
            and bool(re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", str(input_contract["parameters"].get("tenant_id", "")))),
            code,
            f"{test_id} concrete input contract invalid",
        )
        report.require(test.get("command") == ["python", "-m", "tests.contract_runner", "--case", test_id, "--fixture", fixture_id], code, f"{test_id} executable command drift")
        suffix = str(test_id).removeprefix("T-")
        report.require(
            test.get("dataset_contract_id") == f"DATASET-{suffix}-V1"
            and test.get("fixture_path") == f"tests/fixtures/{fixture_id}.json"
            and test.get("oracle_id") == f"ORACLE-{suffix}-V1"
            and test.get("command_contract_id") == "CMD-CONTRACT-RUNNER-V1",
            code,
            f"{test_id} dataset/fixture/oracle/command catalog references drift",
        )
        report.require(test.get("comparator") in allowed_comparators, code, f"{test_id} comparator is not registered")
        threshold = test.get("threshold", {})
        report.require(
            isinstance(threshold, dict)
            and set(threshold) == {"metric", "comparison", "value", "unit"}
            and is_nonempty_string(threshold.get("metric"))
            and threshold.get("comparison") in {"<=", "==", ">="}
            and isinstance(threshold.get("value"), (int, float))
            and not isinstance(threshold.get("value"), bool)
            and is_nonempty_string(threshold.get("unit")),
            code,
            f"{test_id} threshold contract invalid",
        )
        normative_row = normative_by_test.get(test_id, {})
        report.require(
            normative_row.get("title") == test.get("title")
            and normative_row.get("requirement_ids") == test.get("requirement_ids")
            and normative_row.get("procedure_id") == test.get("procedure_id")
            and normative_row.get("comparator") == test.get("comparator")
            and normative_row.get("threshold") == threshold
            and normative_row.get("expected_error") == test.get("expected_error")
            and normative_row.get("fixture_contract_id") == test.get("dataset_contract_id")
            and normative_row.get("command_contract_id") == test.get("command_contract_id"),
            code,
            f"{test_id} title/requirement/procedure/comparator/threshold/error/fixture/command differs from normative semantic map",
        )
        try:
            parameters_digest = hashlib.sha256(canonical_json(input_contract.get("parameters", {})).encode("utf-8")).hexdigest()
        except ValueError as exc:
            report.require(False, code, f"{test_id} fixture parameters are outside canonical subset: {exc}")
            parameters_digest = ""
        expected_catalog_row = {
            "test_id": test_id,
            "dataset_contract_id": f"DATASET-{suffix}-V1",
            "fixture_id": fixture_id,
            "fixture_path": f"tests/fixtures/{fixture_id}.json",
            "dataset_partition": input_contract.get("dataset_partition") if isinstance(input_contract, dict) else None,
            "parameters_sha256": parameters_digest,
            "oracle_id": f"ORACLE-{suffix}-V1",
            "observation_path": f"$.metrics.{threshold.get('metric')}",
            "comparator": test.get("comparator"),
            "comparison": threshold.get("comparison"),
            "expected_value": threshold.get("value"),
            "unit": threshold.get("unit"),
            "expected_error": test.get("expected_error"),
            "command_contract_id": "CMD-CONTRACT-RUNNER-V1",
        }
        report.require(
            semantic_catalog_by_test.get(test_id) == expected_catalog_row,
            code,
            f"{test_id} does not resolve to its exact dataset and machine oracle catalog row",
        )
        negative_path = input_contract.get("parameters", {}).get("negative_path") if isinstance(input_contract, dict) else None
        expected_error = test.get("expected_error")
        report.require(
            expected_error == "NONE" if negative_path is False else bool(re.fullmatch(r"[A-Z][A-Z0-9_]+", str(expected_error))) and expected_error != "NONE",
            code,
            f"{test_id} expected_error does not match positive/negative input",
        )
        evidence = test.get("evidence", {})
        report.require(
            isinstance(evidence, dict)
            and set(evidence) == {"evidence_id", "artifact_media_type", "required_fields", "freshness"}
            and evidence.get("evidence_id") == evidence_id
            and evidence.get("artifact_media_type") == "application/json"
            and evidence.get("required_fields") == ["source_commit", "executed_at_utc", "result", "artifact_sha256", "trace_id", "owner_ids"]
            and evidence.get("freshness") == "FRESH",
            code,
            f"{test_id} evidence contract invalid",
        )
        semantic_projection = {key: value for key, value in test.items() if key != "semantic_case_sha256"}
        try:
            semantic_digest = hashlib.sha256(canonical_json(semantic_projection).encode("utf-8")).hexdigest()
        except ValueError as exc:
            report.require(False, code, f"{test_id} semantic case is outside the canonical subset: {exc}")
            semantic_digest = ""
        report.require(
            test.get("semantic_case_sha256") == semantic_digest,
            code,
            f"{test_id} title/fixture/command/oracle semantic digest mismatch",
        )
    report.require(len(evidence_ids) == len(set(evidence_ids)) == 139, code, "every test must have one unique evidence ID")
    report.require(len({test.get("title") for test in tests if isinstance(test, dict)}) == 139, code, "all 139 test titles must be unique")
    semantic_projection_rows = [
        {key: value for key, value in test.items() if key != "semantic_case_sha256"}
        for test in tests
        if isinstance(test, dict)
    ]
    try:
        aggregate_digest = hashlib.sha256(canonical_json(semantic_projection_rows).encode("utf-8")).hexdigest()
    except ValueError as exc:
        report.require(False, code, f"test semantic aggregate is outside the canonical subset: {exc}")
        aggregate_digest = ""
    report.require(
        aggregate_digest == semantic_contract.get("aggregate_sha256") == TEST_SEMANTIC_AGGREGATE_SHA256,
        code,
        "139-case title/fixture/command/oracle aggregate digest mismatch",
    )
    try:
        catalog_digest = hashlib.sha256(canonical_json(semantic_catalog).encode("utf-8")).hexdigest()
    except ValueError as exc:
        report.require(False, code, f"test semantic catalog is outside canonical subset: {exc}")
        catalog_digest = ""
    report.require(
        catalog_digest == semantic_contract.get("catalog_aggregate_sha256") == TEST_SEMANTIC_CATALOG_SHA256,
        code,
        "139-row dataset/oracle catalog aggregate digest mismatch",
    )

    referenced_tests = {test_id for requirement in all_requirements for test_id in requirement.get("test_ids", []) if isinstance(requirement, dict)}
    report.require(referenced_tests == set(test_ids), code, "test inventory contains an unreferenced test or missing requirement edge")
    report.pass_group(code, "60 RFP, 33 SYS, 28 procedures, and 139 tests are bidirectionally closed", before)


def verify_screens(screens: dict[str, Any], registry: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "SCREENS"
    rows = screens.get("screens", [])
    report.require(screens.get("schema_version") == "screen-route-contracts.v1", code, "schema_version drift")
    authorization = screens.get("authorization_contract", {})
    report.require(
        authorization
        == {
            "allowed_roles": SCREEN_ROLE_VOCABULARY,
            "tenant_guards": TENANT_GUARD_VOCABULARY,
            "deny_unknown_values": True,
        },
        code,
        "authorization vocabulary/deny-unknown contract drift",
    )
    operation_contract = screens.get("operation_resolution_contract", {})
    report.require(
        operation_contract.get("operation_count") == 113
        and operation_contract.get("requirement_link_field") == "requirement_ids"
        and operation_contract.get("test_link_field") == "e2e_test_ids"
        and is_nonempty_string(operation_contract.get("inheritance_rule")),
        code,
        "screen operation resolution contract drift",
    )
    semantic_contract = screens.get("operation_semantic_contract", {})
    report.require(
        semantic_contract
        == {
            "hash_algorithm": "SHA-256",
            "canonicalization": "RFC8785-compatible integer/string subset",
            "operation_projection": "screen_id plus each ordered operation_contract with semantic_case_sha256 omitted",
            "binding_fields": [
                "operation_id", "capability_id", "intent_id", "method", "path_template",
                "request_contract_id", "response_contract_id", "authorization_contract_id", "error_contract_id",
                "owner_ids", "requirement_ids", "test_ids", "evidence_ids",
            ],
            "aggregate_projection": "Screen order then operation order, exactly 113 rows",
            "aggregate_sha256": SCREEN_OPERATION_AGGREGATE_SHA256,
        },
        code,
        "screen operation semantic aggregate contract drift",
    )
    expected_request_catalog = {
        "GET": {"contract_id": "HTTP-REQUEST-GET-V1", "body": "FORBIDDEN", "idempotency_key": "NOT_REQUIRED"},
        "POST": {"contract_id": "HTTP-REQUEST-POST-V1", "body": "CLOSED_JSON_SCHEMA_REQUIRED", "idempotency_key": "REQUIRED"},
        "PUT": {"contract_id": "HTTP-REQUEST-PUT-V1", "body": "CLOSED_JSON_SCHEMA_REQUIRED", "idempotency_key": "REQUIRED"},
        "PATCH": {"contract_id": "HTTP-REQUEST-PATCH-V1", "body": "CLOSED_JSON_SCHEMA_REQUIRED", "idempotency_key": "REQUIRED"},
        "DELETE": {"contract_id": "HTTP-REQUEST-DELETE-V1", "body": "FORBIDDEN", "idempotency_key": "REQUIRED"},
    }
    expected_response_catalog = {
        "GET": {"contract_id": "HTTP-RESPONSE-GET-V1", "success_status": [200], "content_type": "application/json"},
        "POST": {"contract_id": "HTTP-RESPONSE-POST-V1", "success_status": [200, 201, 202], "content_type": "application/json"},
        "PUT": {"contract_id": "HTTP-RESPONSE-PUT-V1", "success_status": [200], "content_type": "application/json"},
        "PATCH": {"contract_id": "HTTP-RESPONSE-PATCH-V1", "success_status": [200], "content_type": "application/json"},
        "DELETE": {"contract_id": "HTTP-RESPONSE-DELETE-V1", "success_status": [204], "content_type": "NONE"},
    }
    expected_error_catalog = {
        "READ": {"contract_id": "HTTP-ERROR-READ-V1", "codes": ["AUTHENTICATION_REQUIRED", "AUTHORIZATION_DENIED", "TENANT_SCOPE_VIOLATION", "NOT_FOUND"]},
        "MUTATION": {"contract_id": "HTTP-ERROR-MUTATION-V1", "codes": ["AUTHENTICATION_REQUIRED", "AUTHORIZATION_DENIED", "TENANT_SCOPE_VIOLATION", "VALIDATION_FAILED", "CONFLICT", "IDEMPOTENCY_REPLAY"]},
        "HEALTH": {"contract_id": "HTTP-ERROR-HEALTH-V1", "codes": ["DEPENDENCY_UNAVAILABLE"]},
    }
    shared_catalogs = screens.get("operation_shared_catalogs", {})
    report.require(
        shared_catalogs.get("request") == expected_request_catalog
        and shared_catalogs.get("response") == expected_response_catalog
        and shared_catalogs.get("error") == expected_error_catalog,
        code,
        "canonical API request/response/error catalogs drift",
    )
    report.require(screens.get("screen_count") == 36 and isinstance(rows, list) and len(rows) == 36, code, "screen inventory must contain exactly 36 rows")
    if not isinstance(rows, list):
        return
    expected_screen_ids = [f"PUB-{number:03d}" for number in range(1, 5)] + [f"TCH-{number:03d}" for number in range(1, 17)] + [f"ADM-{number:03d}" for number in range(1, 17)]
    screen_ids = [row.get("screen_id") for row in rows if isinstance(row, dict)]
    report.require(screen_ids == expected_screen_ids, code, "screen IDs/order must be PUB-001..004, TCH-001..016, ADM-001..016")
    expected_authorization_catalog: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        screen_id = row.get("screen_id")
        if screen_id == "TCH-015":
            expected_authorization_catalog.extend(
                [
                    {
                        "contract_id": "AUTHZ-TCH-015-DRAFT-READ-V1",
                        "screen_id": "TCH-015",
                        "allowed_roles": ["TEACHER", "CONTENT_REVIEWER"],
                        "tenant_guard": "ACTIVE_TENANT_MEMBERSHIP",
                        "unknown_role_or_guard": "DENY",
                    },
                    {
                        "contract_id": "AUTHZ-TCH-015-DRAFT-EDIT-V1",
                        "screen_id": "TCH-015",
                        "allowed_roles": ["TEACHER"],
                        "tenant_guard": "ACTIVE_TENANT_OWNERSHIP",
                        "unknown_role_or_guard": "DENY",
                    },
                    {
                        "contract_id": "AUTHZ-TCH-015-DRAFT-REVIEW-V1",
                        "screen_id": "TCH-015",
                        "allowed_roles": ["TEACHER", "CONTENT_REVIEWER"],
                        "tenant_guard": "ACTIVE_TENANT_MEMBERSHIP",
                        "unknown_role_or_guard": "DENY",
                    },
                    {
                        "contract_id": "AUTHZ-TCH-015-DRAFT-EXPORT-V1",
                        "screen_id": "TCH-015",
                        "allowed_roles": ["TEACHER"],
                        "tenant_guard": "ACTIVE_TENANT_OWNERSHIP",
                        "unknown_role_or_guard": "DENY",
                    },
                ]
            )
        else:
            expected_authorization_catalog.append(
                {
                    "contract_id": f"AUTHZ-{screen_id}-V1",
                    "screen_id": screen_id,
                    "allowed_roles": row.get("allowed_roles"),
                    "tenant_guard": row.get("tenant_guard"),
                    "unknown_role_or_guard": "DENY",
                }
            )
    report.require(
        shared_catalogs.get("authorization") == expected_authorization_catalog,
        code,
        "39-row operation-aware canonical authorization catalog drift",
    )
    authorization_by_id = {
        row.get("contract_id"): row
        for row in expected_authorization_catalog
        if is_nonempty_string(row.get("contract_id"))
    }
    tch015_operation_authorization = {
        "GET /api/v1/drafts/{id}": "AUTHZ-TCH-015-DRAFT-READ-V1",
        "PATCH /api/v1/drafts/{id}": "AUTHZ-TCH-015-DRAFT-EDIT-V1",
        "POST /api/v1/drafts/{id}/review": "AUTHZ-TCH-015-DRAFT-REVIEW-V1",
        "POST /api/v1/drafts/{id}/export": "AUTHZ-TCH-015-DRAFT-EXPORT-V1",
    }
    tests = [test for test in registry.get("tests", []) if isinstance(test, dict)]
    test_by_id = {test.get("test_id"): test for test in tests}
    test_ids = set(test_by_id)
    requirements = [
        requirement
        for requirement in [*registry.get("rfp_requirements", []), *registry.get("system_requirements", [])]
        if isinstance(requirement, dict)
    ]
    expected_requirements_by_screen = {
        screen_id: [
            requirement.get("requirement_id")
            for requirement in requirements
            if screen_id in requirement.get("screen_ids", [])
        ]
        for screen_id in expected_screen_ids
    }
    required_keys = {
        "screen_id",
        "route",
        "route_aliases",
        "allowed_roles",
        "tenant_guard",
        "api_operations",
        "events",
        "state_ids",
        "requirement_ids",
        "e2e_test_ids",
        "operation_contracts",
    }
    routes: list[str] = []
    operations: list[str] = []
    operation_semantic_rows: list[dict[str, Any]] = []
    capability_ids: list[str] = []
    intent_ids: list[str] = []
    for row in rows:
        if not isinstance(row, dict):
            report.require(False, code, "screen row must be an object")
            continue
        screen_id = row.get("screen_id", "<missing>")
        report.require(set(row) == required_keys, code, f"{screen_id} key contract drift")
        route = row.get("route")
        aliases = row.get("route_aliases")
        report.require(is_nonempty_string(route) and isinstance(aliases, list), code, f"{screen_id} route/aliases invalid")
        row_routes = [route, *(aliases if isinstance(aliases, list) else [])]
        for item in row_routes:
            valid = isinstance(item, str) and item.startswith("/") and "\\" not in item and "%" not in item and (item == "/" or not any(part in ("", ".", "..") for part in item.split("/")[1:]))
            report.require(valid, code, f"{screen_id} unsafe route: {item!r}")
            if isinstance(item, str):
                routes.append(item)
        for field in ("allowed_roles", "api_operations", "events", "state_ids", "requirement_ids", "e2e_test_ids"):
            report.require(is_nonempty_unique_strings(row.get(field)), code, f"{screen_id}.{field} must be nonempty and unique")
        report.require(
            all(role in SCREEN_ROLE_VOCABULARY for role in row.get("allowed_roles", [])),
            code,
            f"{screen_id} contains an unknown or wildcard role",
        )
        report.require(
            row.get("tenant_guard") in TENANT_GUARD_VOCABULARY,
            code,
            f"{screen_id} contains an unknown or wildcard tenant guard",
        )
        requirement_ids = row.get("requirement_ids", [])
        report.require(
            requirement_ids == expected_requirements_by_screen.get(screen_id),
            code,
            f"{screen_id}.requirement_ids must equal the ordered reverse requirement screen_ids edges",
        )
        for operation in row.get("api_operations", []):
            operation_is_valid = re.fullmatch(r"(?:GET|POST|PUT|PATCH|DELETE) /api/v1/[A-Za-z0-9_{}:/.-]+", operation) is not None or operation == "GET /health/ready"
            report.require(operation_is_valid, code, f"{screen_id} malformed API operation: {operation}")
            operations.append(operation)
        for test_id in row.get("e2e_test_ids", []):
            report.require(test_id in test_ids, code, f"{screen_id} references unknown E2E test: {test_id}")
            test = test_by_id.get(test_id, {})
            report.require(
                bool(set(requirement_ids) & set(test.get("requirement_ids", []))),
                code,
                f"{screen_id} test {test_id} has no shared requirement edge",
            )
        linked_test_requirements = {
            requirement_id
            for test_id in row.get("e2e_test_ids", [])
            for requirement_id in test_by_id.get(test_id, {}).get("requirement_ids", [])
        }
        report.require(
            bool(set(requirement_ids) & linked_test_requirements),
            code,
            f"{screen_id} operations have no requirement/capability linked to an executable E2E test",
        )
        operation_contracts = row.get("operation_contracts", [])
        report.require(isinstance(operation_contracts, list) and len(operation_contracts) == len(row.get("api_operations", [])), code, f"{screen_id} operation contract cardinality drift")
        evidence_ids = [test_by_id.get(test_id, {}).get("evidence_id") for test_id in row.get("e2e_test_ids", [])]
        for index, operation_contract in enumerate(operation_contracts if isinstance(operation_contracts, list) else []):
            operation_id = row.get("api_operations", [])[index] if index < len(row.get("api_operations", [])) else "<missing>"
            method, separator, path_template = str(operation_id).partition(" ")
            expected_capability_id = f"CAP-{screen_id}-{index + 1:03d}"
            path_tokens = re.sub(r"[^A-Za-z0-9]+", "-", path_template).strip("-").upper()
            expected_intent_id = f"INTENT-{method}-{path_tokens}"
            report.require(
                isinstance(operation_contract, dict)
                and set(operation_contract)
                == {
                    "operation_id", "capability_id", "intent_id", "method", "path_template", "owner_ids",
                    "request_contract_id", "response_contract_id", "authorization_contract_id", "error_contract_id",
                    "requirement_ids", "test_ids", "evidence_ids", "semantic_case_sha256",
                }
                and operation_contract.get("operation_id") == operation_id
                and separator == " "
                and operation_contract.get("method") == method
                and operation_contract.get("path_template") == path_template
                and operation_contract.get("capability_id") == expected_capability_id
                and operation_contract.get("intent_id") == expected_intent_id,
                code,
                f"{screen_id} operation {operation_id} identity/method/path/capability/intent contract drift",
            )
            expected_error_kind = "HEALTH" if path_template == "/health/ready" else ("READ" if method == "GET" else "MUTATION")
            expected_authorization_id = (
                tch015_operation_authorization.get(operation_id)
                if screen_id == "TCH-015"
                else f"AUTHZ-{screen_id}-V1"
            )
            authorization_row = authorization_by_id.get(expected_authorization_id, {})
            report.require(
                operation_contract.get("request_contract_id") == expected_request_catalog.get(method, {}).get("contract_id")
                and operation_contract.get("response_contract_id") == expected_response_catalog.get(method, {}).get("contract_id")
                and operation_contract.get("authorization_contract_id") == expected_authorization_id
                and authorization_row.get("screen_id") == screen_id
                and operation_contract.get("error_contract_id") == expected_error_catalog.get(expected_error_kind, {}).get("contract_id"),
                code,
                f"{screen_id} operation {operation_id} request/response/auth/error catalog binding drift",
            )
            contract_requirements = operation_contract.get("requirement_ids", []) if isinstance(operation_contract, dict) else []
            contract_tests = operation_contract.get("test_ids", []) if isinstance(operation_contract, dict) else []
            contract_evidence = operation_contract.get("evidence_ids", []) if isinstance(operation_contract, dict) else []
            contract_owners = operation_contract.get("owner_ids", []) if isinstance(operation_contract, dict) else []
            report.require(
                is_nonempty_unique_strings(contract_requirements)
                and set(contract_requirements) <= set(requirement_ids),
                code,
                f"{screen_id} operation {operation_id} requirement ownership is not a focused screen subset",
            )
            report.require(
                is_nonempty_unique_strings(contract_tests)
                and len(contract_tests) == 1
                and set(contract_tests) <= set(row.get("e2e_test_ids", [])),
                code,
                f"{screen_id} operation {operation_id} must bind one canonical executable test",
            )
            report.require(
                contract_evidence == [test_by_id.get(test_id, {}).get("evidence_id") for test_id in contract_tests],
                code,
                f"{screen_id} operation {operation_id} evidence does not exactly bind its test",
            )
            report.require(
                all(
                    bool(set(contract_requirements) & set(test_by_id.get(test_id, {}).get("requirement_ids", [])))
                    for test_id in contract_tests
                ),
                code,
                f"{screen_id} operation {operation_id} test has no shared canonical requirement",
            )
            expected_owners: list[str] = []
            for requirement_id in contract_requirements:
                requirement = next((item for item in requirements if item.get("requirement_id") == requirement_id), {})
                for owner_id in requirement.get("owner_ids", []):
                    if owner_id not in expected_owners:
                        expected_owners.append(owner_id)
            for test_id in contract_tests:
                for owner_id in test_by_id.get(test_id, {}).get("owner_ids", []):
                    if owner_id not in expected_owners:
                        expected_owners.append(owner_id)
            report.require(
                contract_owners == expected_owners and bool(expected_owners),
                code,
                f"{screen_id} operation {operation_id} owner union drift",
            )
            direct_requirements = [
                requirement.get("requirement_id")
                for requirement in requirements
                if operation_id in requirement.get("api_operation_ids", [])
                and requirement.get("requirement_id") in requirement_ids
            ]
            if direct_requirements:
                report.require(
                    contract_requirements == direct_requirements,
                    code,
                    f"{screen_id} operation {operation_id} omits a direct requirement API edge",
                )
            if len(row.get("api_operations", [])) > 1:
                report.require(
                    contract_tests != row.get("e2e_test_ids"),
                    code,
                    f"{screen_id} operation {operation_id} copied the screen-wide test closure",
                )
            projection = {
                key: value
                for key, value in operation_contract.items()
                if key != "semantic_case_sha256"
            } if isinstance(operation_contract, dict) else {}
            try:
                semantic_digest = hashlib.sha256(canonical_json(projection).encode("utf-8")).hexdigest()
            except ValueError as exc:
                report.require(False, code, f"{screen_id} operation {operation_id} semantic projection invalid: {exc}")
                semantic_digest = ""
            report.require(
                operation_contract.get("semantic_case_sha256") == semantic_digest if isinstance(operation_contract, dict) else False,
                code,
                f"{screen_id} operation {operation_id} semantic case digest mismatch",
            )
            operation_semantic_rows.append({"screen_id": screen_id, **projection})
            capability_ids.append(operation_contract.get("capability_id") if isinstance(operation_contract, dict) else None)
            intent_ids.append(operation_contract.get("intent_id") if isinstance(operation_contract, dict) else None)

    report.require(len(routes) == len(set(routes)) == 42, code, "primary+alias routes must contain exactly 42 unique paths")
    report.require(len(operations) == len(set(operations)) == 113, code, "API operation references must contain exactly 113 unique method/path pairs")
    operation_contract_ids = [
        contract.get("operation_id")
        for row in rows if isinstance(row, dict)
        for contract in row.get("operation_contracts", []) if isinstance(contract, dict)
    ]
    report.require(operation_contract_ids == operations and len(set(operation_contract_ids)) == 113, code, "113 operation contracts must exactly preserve screen operation order")
    report.require(len(set(capability_ids)) == len(set(intent_ids)) == 113, code, "113 capability and intent IDs must be unique")
    try:
        operation_aggregate = hashlib.sha256(canonical_json(operation_semantic_rows).encode("utf-8")).hexdigest()
    except ValueError as exc:
        report.require(False, code, f"operation semantic aggregate invalid: {exc}")
        operation_aggregate = ""
    report.require(
        operation_aggregate == semantic_contract.get("aggregate_sha256") == SCREEN_OPERATION_AGGREGATE_SHA256,
        code,
        "113-operation semantic/owner/requirement/test aggregate digest mismatch",
    )
    requirement_screen_ids = {
        screen_id
        for requirement in requirements
        for screen_id in requirement.get("screen_ids", [])
    }
    report.require(requirement_screen_ids == set(screen_ids), code, "all screens must resolve bidirectionally to at least one requirement")

    by_id = {row.get("screen_id"): row for row in rows if isinstance(row, dict)}
    public_auth = by_id.get("PUB-004", {})
    admin_access = by_id.get("ADM-012", {})
    report.require({"/auth/mfa/challenge", "/auth/mfa/recovery"} <= set(public_auth.get("route_aliases", [])), code, "public MFA challenge/recovery routes are missing")
    report.require({"POST /api/v1/auth/mfa/challenges", "POST /api/v1/auth/mfa/challenges/{challenge_id}/verify", "POST /api/v1/auth/mfa/recovery"} <= set(public_auth.get("api_operations", [])), code, "public MFA lifecycle operations are missing")
    report.require({"/admin/access/mfa-enrollment", "/admin/access/mfa-recovery"} <= set(admin_access.get("route_aliases", [])), code, "admin MFA enrollment/recovery routes are missing")
    report.require({"POST /api/v1/auth/mfa/enrollments", "POST /api/v1/auth/mfa/enrollments/{id}/verify", "POST /api/v1/auth/mfa/recovery-codes/rotate"} <= set(admin_access.get("api_operations", [])), code, "admin MFA lifecycle operations are missing")
    report.pass_group(code, "36 screens, 42 routes, and 113 API operations resolve to registered tests", before)


def verify_api_operation_resolution(registry: dict[str, Any], screens: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "API_RESOLUTION"
    requirements = [
        requirement
        for requirement in [*registry.get("rfp_requirements", []), *registry.get("system_requirements", [])]
        if isinstance(requirement, dict)
    ]
    requirement_by_id = {
        requirement.get("requirement_id"): requirement
        for requirement in requirements
        if is_nonempty_string(requirement.get("requirement_id"))
    }
    test_by_id = {
        test.get("test_id"): test
        for test in registry.get("tests", [])
        if isinstance(test, dict) and is_nonempty_string(test.get("test_id"))
    }
    requirement_operations = {
        operation
        for requirement in requirements
        for operation in requirement.get("api_operation_ids", [])
        if is_nonempty_string(operation)
    }
    screen_operations = {
        operation
        for screen in screens.get("screens", [])
        if isinstance(screen, dict)
        for operation in screen.get("api_operations", [])
        if is_nonempty_string(operation)
    }
    intersection = requirement_operations & screen_operations
    requirement_only = requirement_operations - screen_operations
    screen_only = screen_operations - requirement_operations
    report.require(len(requirement_operations) == 28, code, "requirement API inventory must contain exactly 28 unique operations")
    report.require(len(screen_operations) == 113, code, "screen API inventory must contain exactly 113 unique operations")
    report.require(len(intersection) == 27, code, "requirement/screen API intersection must contain exactly 27 operations")
    report.require(len(requirement_only) == 1, code, "requirement-only API inventory must contain exactly one operation")
    report.require(len(screen_only) == 86, code, "screen-only API inventory must contain exactly 86 operations")

    contract = registry.get("api_operation_resolution_contract", {})
    expected_counts = {
        "requirement_operation_count": 28,
        "screen_operation_count": 113,
        "intersection_count": 27,
        "requirement_only_count": 1,
        "screen_only_count": 86,
    }
    report.require(
        all(contract.get(key) == value for key, value in expected_counts.items())
        and is_nonempty_string(contract.get("screen_resolution_rule")),
        code,
        "API resolution count/rule contract drift",
    )
    report.require(
        contract.get("operation_contract_field") == "operation_contracts"
        and is_nonempty_string(contract.get("row_closure_rule")),
        code,
        "row-level operation closure contract is missing",
    )
    service_only = contract.get("service_only_operations", [])
    report.require(isinstance(service_only, list) and len(service_only) == 1, code, "service-only allowlist must contain exactly one operation")
    service_operation_ids = {
        row.get("operation_id")
        for row in service_only
        if isinstance(row, dict) and is_nonempty_string(row.get("operation_id"))
    }
    report.require(
        service_operation_ids == requirement_only == {"POST /internal/ai/v1/responses"},
        code,
        "requirement-only operation must resolve to the pinned AI gateway service allowlist",
    )
    for row in service_only if isinstance(service_only, list) else []:
        if not isinstance(row, dict):
            report.require(False, code, "service-only operation row must be an object")
            continue
        operation_id = row.get("operation_id", "<missing>")
        report.require(
            set(row)
            == {"operation_id", "requirement_ids", "owner_ids", "test_ids", "intent_id"},
            code,
            f"{operation_id} service-only row key contract drift",
        )
        requirement_ids = row.get("requirement_ids", [])
        owner_ids = row.get("owner_ids", [])
        test_ids = row.get("test_ids", [])
        report.require(requirement_ids == ["SYS-F-013"], code, f"{operation_id} requirement ownership drift")
        report.require(owner_ids == ["OWN-AI", "OWN-ARCH"], code, f"{operation_id} technical owner drift")
        report.require(test_ids == ["T-ARCH-001", "T-KPI-005"], code, f"{operation_id} executable test contract drift")
        report.require(row.get("intent_id") == "CAP-AI-GATEWAY-STRUCTURED-RESPONSE", code, f"{operation_id} capability intent drift")
        for requirement_id in requirement_ids:
            requirement = requirement_by_id.get(requirement_id)
            report.require(requirement is not None, code, f"{operation_id} references unknown requirement: {requirement_id}")
            if requirement is None:
                continue
            report.require(operation_id in requirement.get("api_operation_ids", []), code, f"{operation_id} is absent from {requirement_id}.api_operation_ids")
            report.require(set(owner_ids) <= set(requirement.get("owner_ids", [])), code, f"{operation_id} owner is not assigned to {requirement_id}")
            for test_id in test_ids:
                test = test_by_id.get(test_id)
                report.require(test is not None, code, f"{operation_id} references unknown test: {test_id}")
                if test is not None:
                    report.require(
                        requirement_id in test.get("requirement_ids", [])
                        and test_id in requirement.get("test_ids", []),
                        code,
                        f"{operation_id} test {test_id} is not bidirectionally linked to {requirement_id}",
                    )
    report.require(
        all(operation in screen_operations or operation in service_operation_ids for operation in requirement_operations),
        code,
        "a requirement API operation is neither screen-resolved nor explicitly service-only",
    )
    report.pass_group(code, "28 requirement operations close over 113 screen operations plus one owned/tested service-only operation", before)


def verify_entity_catalog(catalog: dict[str, Any], registry: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "ENTITY_CATALOG"
    requirements = [
        row for row in [*registry.get("rfp_requirements", []), *registry.get("system_requirements", [])]
        if isinstance(row, dict)
    ]
    expected_entity_ids = sorted({entity for row in requirements for entity in row.get("data_entity_ids", [])})
    entities = catalog.get("entities", [])
    report.require(catalog.get("schema_version") == "entity-catalog.v1", code, "entity catalog schema version drift")
    report.require(catalog.get("entity_count") == 58 and len(expected_entity_ids) == 58 and isinstance(entities, list) and len(entities) == 58, code, "entity catalog must contain exactly 58 rows")
    report.require(catalog.get("classification_vocabulary") == ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"], code, "entity classification vocabulary drift")
    report.require(catalog.get("tenant_scope_vocabulary") == ["GLOBAL", "TENANT"] and catalog.get("unknown_classification_default") == "RESTRICTED", code, "entity tenant/default classification contract drift")
    report.require(
        catalog.get("ingress_default_policy")
        == {
            "unknown_teacher_free_text": {"classification": "RESTRICTED", "tenant_scope": "TENANT"},
            "raw_or_scanned_upload": {"classification": "RESTRICTED", "tenant_scope": "TENANT"},
            "public_promotion": "EXPLICIT_RIGHTS_REVIEW_AND_PUBLICATION_DECISION_REQUIRED",
        },
        code,
        "unknown teacher free text/raw-scanned upload default policy drift",
    )
    report.require(is_nonempty_string(catalog.get("reverse_link_rule")), code, "entity reverse-link rule missing")
    entity_ids = [row.get("entity_id") for row in entities if isinstance(row, dict)]
    report.require(entity_ids == expected_entity_ids and len(set(entity_ids)) == 58, code, "catalog entity IDs must exactly equal the sorted requirement data_entity_ids union")
    for row in entities if isinstance(entities, list) else []:
        if not isinstance(row, dict):
            report.require(False, code, "entity row must be an object")
            continue
        entity_id = row.get("entity_id", "<missing>")
        report.require(
            set(row) == {"entity_id", "domain", "classification", "tenant_scope", "retention_policy_id", "owner_ids", "schema_id", "deletion_policy", "requirement_ids"},
            code,
            f"{entity_id} key contract drift",
        )
        linked = [requirement for requirement in requirements if entity_id in requirement.get("data_entity_ids", [])]
        expected_requirements = [requirement.get("requirement_id") for requirement in linked]
        expected_owners: list[str] = []
        for requirement in linked:
            for owner in requirement.get("owner_ids", []):
                if owner not in expected_owners:
                    expected_owners.append(owner)
        report.require(row.get("requirement_ids") == expected_requirements and bool(expected_requirements), code, f"{entity_id} requirement reverse edges drift")
        report.require(row.get("owner_ids") == expected_owners and bool(expected_owners), code, f"{entity_id} owner reverse union drift")
        report.require(row.get("classification") in catalog.get("classification_vocabulary", []), code, f"{entity_id} unknown classification")
        report.require(row.get("tenant_scope") in catalog.get("tenant_scope_vocabulary", []), code, f"{entity_id} unknown tenant scope")
        report.require(bool(re.fullmatch(r"[A-Z][A-Z0-9_]+", str(row.get("domain", "")))), code, f"{entity_id} domain invalid")
        report.require(bool(re.fullmatch(r"RET-[A-Z0-9-]+", str(row.get("retention_policy_id", "")))), code, f"{entity_id} retention policy invalid")
        report.require(bool(re.fullmatch(r"urn:yonlab:entity:[a-z0-9-]+:v1", str(row.get("schema_id", "")))), code, f"{entity_id} schema ID invalid")
        report.require(row.get("deletion_policy") in {"IMMUTABLE_APPEND_ONLY", "CRYPTO_ERASE_OR_TOMBSTONE", "VERSIONED_DELETE"}, code, f"{entity_id} deletion policy invalid")
        if row.get("classification") == "RESTRICTED":
            report.require(row.get("tenant_scope") == "TENANT", code, f"{entity_id} RESTRICTED entity must be tenant scoped")
        if entity_id in {"SourceDocument", "TeacherContext"}:
            report.require(
                row.get("classification") == "RESTRICTED" and row.get("tenant_scope") == "TENANT",
                code,
                f"{entity_id} must remain RESTRICTED and tenant scoped",
            )
    report.pass_group(code, "58 entities reverse-link requirements and owners with explicit classification, retention, schema, scope, and deletion", before)


def verify_kpi_matrix(matrix: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "KPI005"
    expected_tasks = [
        "diagnosis.evidence.extract",
        "diagnosis.next_question.compose",
        "persona.explanation.compose",
        "recommendation.explanation.compose",
        "document.query.rewrite",
        "document.rerank",
        "document.grounded_answer",
        "draft.hwpx.section.compose",
        "document.metadata.tag",
    ]
    tasks = matrix.get("tasks", [])
    cells = matrix.get("coverage_cells", [])
    task_names = [task.get("task") for task in tasks if isinstance(task, dict)]
    report.require(matrix.get("schema_version") == "kpi-005-matrix.v1" and matrix.get("kpi_id") == "KPI-005", code, "matrix identity drift")
    report.require(task_names == expected_tasks and len(set(task_names)) == 9, code, "structured task inventory must be the exact ordered nine-task set")
    report.require(all(isinstance(task, dict) and set(task) == {"task", "schema_id", "fallback_output"} and is_nonempty_string(task.get("schema_id")) and is_nonempty_string(task.get("fallback_output")) for task in tasks), code, "task schema/fallback contract drift")
    axes = matrix.get("coverage_axes", {})
    report.require(axes.get("provider_paths") == ["INTERNAL_SLLM", "EXTERNAL_OPENAI", "APPROVED_MODEL_FALLBACK"], code, "provider path axis drift")
    report.require(axes.get("fallback_classes") == ["PRIMARY", "CROSS_PROVIDER_FALLBACK"], code, "fallback class axis drift")
    expected_paths = [
        ("INTERNAL_SLLM", "PRIMARY"),
        ("EXTERNAL_OPENAI", "PRIMARY"),
        ("APPROVED_MODEL_FALLBACK", "CROSS_PROVIDER_FALLBACK"),
    ]
    expected_cells = [(task, provider, fallback) for task in expected_tasks for provider, fallback in expected_paths]
    actual_cells = [
        (cell.get("task"), cell.get("provider_path"), cell.get("fallback_class"))
        for cell in cells
        if isinstance(cell, dict)
    ]
    cell_ids = [cell.get("cell_id") for cell in cells if isinstance(cell, dict)]
    report.require(isinstance(cells, list) and actual_cells == expected_cells, code, "coverage cells must be the exact 9x3 task/provider/fallback product")
    report.require(cell_ids == [f"KPI005-C{number:03d}" for number in range(1, 28)], code, "coverage cell IDs must be KPI005-C001..C027")
    report.require(all(isinstance(cell, dict) and set(cell) == {"cell_id", "task", "provider_path", "fallback_class"} for cell in cells), code, "coverage cell key contract drift")
    defaults = matrix.get("coverage_cell_defaults", {})
    report.require(defaults == {"denominator": 1000, "minimum_success_rate": 0.995, "initial_attempts": 1, "maximum_schema_repairs": 1, "required_status": "PASS"}, code, "coverage cell defaults drift")
    attempt = matrix.get("attempt_policy", {})
    report.require(attempt.get("initial_attempts") == 1 and attempt.get("maximum_schema_repairs") == 1 and attempt.get("second_repair_result") == "FAIL" and attempt.get("missing_or_unknown_schema_result") == "FAIL", code, "attempt/repair fail-closed policy drift")
    sample = matrix.get("sample_policy", {})
    acceptance = matrix.get("acceptance", {})
    report.require(sample.get("minimum_requests_per_task_provider_path") == 1000 and sample.get("minimum_total_requests") == 27000, code, "sample denominator drift")
    report.require(acceptance.get("overall_minimum") == 0.998 and acceptance.get("per_task_provider_path_minimum") == 0.995 and acceptance.get("unknown_or_unexecuted_cell_status") == "BLOCKED", code, "acceptance threshold drift")
    report.require(matrix.get("required_case_count") == 27 and defaults.get("denominator", 0) * len(cells) == 27000, code, "27-cell denominator arithmetic drift")
    report.pass_group(code, "nine tasks map to 27 explicit cells and a 27,000-request minimum", before)


def verify_diagnosis_vectors(vectors: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "DIAGNOSIS_GOLDEN"
    scale = vectors.get("scale")
    expected_ids = ["GV-SCORE-001", "GV-SCORE-DEDUP-001", "GV-SCORE-INVALID-001", "GV-PERSONA-001", "GV-PERSONA-002", "GV-REC-001", "GV-REC-002", "GV-TIE-001"]
    rows = vectors.get("vectors", [])
    by_id = {row.get("id"): row for row in rows if isinstance(row, dict)}
    report.require(vectors.get("schema_version") == "diagnosis-golden-vectors.v1" and scale == 1_000_000 and vectors.get("canonicalization") == "JCS", code, "golden vector identity/scale drift")
    report.require(vectors.get("policy_versions") == ["ScoringPolicyVersion=diagnosis-scoring.v1", "PersonaInferencePolicyVersion=persona-inference.v1", "RecommendationPolicyVersion=recommendation-ranking.v1"], code, "policy version inventory drift")
    report.require([row.get("id") for row in rows if isinstance(row, dict)] == expected_ids, code, "golden vector IDs/order drift")
    required_evidence_fields = {"evidence_id", "turn_id", "turn_sequence", "indicator_id", "anchor", "anchor_count", "confidence_decimal", "span_start_codepoint", "span_end_codepoint", "quoted_span", "schema_version"}
    report.require(set(vectors.get("evidence_span_contract", {}).get("required", [])) == required_evidence_fields, code, "EvidenceSpan required field contract drift")

    def validate_evidence(evidence: dict[str, Any], anchor_count: int) -> bool:
        valid = required_evidence_fields <= set(evidence)
        try:
            valid = valid and str(uuid.UUID(evidence["evidence_id"])) == evidence["evidence_id"]
            valid = valid and str(uuid.UUID(evidence["turn_id"])) == evidence["turn_id"]
            valid = valid and fixed_int(evidence["confidence_decimal"], 6) <= scale
            valid = valid and evidence["anchor_count"] == anchor_count and 0 <= evidence["anchor"] < anchor_count
            valid = valid and isinstance(evidence["turn_sequence"], int) and evidence["turn_sequence"] >= 0
            valid = valid and 0 <= evidence["span_start_codepoint"] < evidence["span_end_codepoint"]
            valid = valid and unicodedata.normalize("NFC", evidence["quoted_span"]) == evidence["quoted_span"]
            valid = valid and len(evidence["quoted_span"]) == evidence["span_end_codepoint"] - evidence["span_start_codepoint"]
        except (KeyError, TypeError, ValueError, AttributeError):
            return False
        return valid

    def scoring_result(row: dict[str, Any]) -> tuple[int, str, str]:
        source = row["input"]
        anchor_count = source["anchor_count"]
        indicator_weight = fixed_int(source["indicator_weight_decimal"], 6)
        dimension_weight = fixed_int(source["dimension_weight_decimal"], 6)
        evidence_rows = source["evidence"]
        if not all(validate_evidence(item, anchor_count) for item in evidence_rows):
            raise ValueError("invalid evidence")
        selected: dict[tuple[str, int], dict[str, Any]] = {}
        for item in evidence_rows:
            key = (item["indicator_id"], item["turn_sequence"])
            candidate_key = (-fixed_int(item["confidence_decimal"], 6), item["span_start_codepoint"], item["evidence_id"].encode("utf-8"))
            current = selected.get(key)
            if current is None:
                selected[key] = item
            else:
                current_key = (-fixed_int(current["confidence_decimal"], 6), current["span_start_codepoint"], current["evidence_id"].encode("utf-8"))
                if candidate_key < current_key:
                    selected[key] = item
        ordered = sorted(selected.values(), key=lambda item: (item["indicator_id"].encode("utf-8"), item["turn_sequence"], item["span_start_codepoint"], item["evidence_id"].encode("utf-8")))
        numerator = 0
        denominator = 0
        for item in ordered:
            confidence = fixed_int(item["confidence_decimal"], 6)
            x_value = div_half_up(100 * scale * item["anchor"], anchor_count - 1)
            quality = indicator_weight * confidence
            numerator += quality * x_value
            denominator += quality
        dimension_score = div_half_up(numerator, denominator)
        overall_score = div_half_up(dimension_weight * dimension_score, dimension_weight)
        return overall_score, fixed_string(overall_score, 6), ordered[0]["evidence_id"]

    try:
        score_value, score_decimal, _ = scoring_result(by_id["GV-SCORE-001"])
        expected = by_id["GV-SCORE-001"]["expected"]
        report.require(expected.get("dimension_score_microunit") == score_value == expected.get("overall_score_microunit") and expected.get("dimension_score_decimal") == score_decimal == expected.get("overall_score_decimal"), code, "GV-SCORE-001 arithmetic mismatch")
        dedup_value, _, selected_id = scoring_result(by_id["GV-SCORE-DEDUP-001"])
        dedup_expected = by_id["GV-SCORE-DEDUP-001"]["expected"]
        report.require(dedup_expected.get("selected_evidence_id") == selected_id and dedup_expected.get("dimension_score_microunit") == dedup_value == dedup_expected.get("overall_score_microunit"), code, "GV-SCORE-DEDUP-001 selection/arithmetic mismatch")
    except (KeyError, TypeError, ValueError, ZeroDivisionError) as exc:
        report.require(False, code, f"scoring vector is not executable: {exc}")

    invalid = by_id.get("GV-SCORE-INVALID-001", {})
    invalid_input = invalid.get("input", {})
    invalid_expected = invalid.get("expected", {})
    report.require(invalid_input.get("anchor", -1) >= invalid_input.get("anchor_count", 0) and invalid_expected == {"status": "INVALID_EVIDENCE", "numeric_score_present": False}, code, "invalid-evidence vector drift")

    persona_equal = by_id.get("GV-PERSONA-001", {})
    persona_input = persona_equal.get("input", {})
    persona_expected = persona_equal.get("expected", {})
    try:
        report.require(len(persona_input.get("profile_order", [])) == 12 and all(fixed_int(value, 12) == 0 for value in persona_input.get("logit_decimal", [])), code, "equal-logit persona input drift")
    except ValueError as exc:
        report.require(False, code, str(exc))
    profile_probabilities = [83_334] * 4 + [83_333] * 8
    family_probabilities = [sum(profile_probabilities[index:index + 2]) for index in range(0, 12, 2)]
    report.require(persona_expected.get("profile_probability_microunit") == profile_probabilities and persona_expected.get("family_probability_microunit") == family_probabilities and persona_expected.get("probability_sum") == sum(profile_probabilities) == 1_000_000 and persona_expected.get("family_classification") == "MIXED_OR_UNDETERMINED", code, "equal-logit largest-remainder vector mismatch")
    persona_boundary = by_id.get("GV-PERSONA-002", {})
    boundary_input = persona_boundary.get("input", {}).get("family_probability_microunit", [])
    boundary_expected = persona_boundary.get("expected", {})
    report.require(sum(boundary_input) == 1_000_000 and max(boundary_input) == 450_000 and boundary_expected.get("family_classification") == "P-01" and boundary_expected.get("mixed") is False, code, "persona 0.45 boundary vector mismatch")

    weights = [400_000, 200_000, 150_000, 100_000, 100_000, 50_000]
    for vector_id in ("GV-REC-001", "GV-REC-002"):
        row = by_id.get(vector_id, {})
        source = row.get("input", {})
        features = source.get("feature_microunit", [])
        expected = row.get("expected", {})
        if len(features) != 6 or not all(isinstance(value, int) and 0 <= value <= scale for value in features):
            report.require(False, code, f"{vector_id} feature vector invalid")
            continue
        base = div_half_up(sum(weight * value for weight, value in zip(weights, features)), scale)
        novelty = scale if source.get("selected_tags") == [] else scale - source.get("maximum_jaccard_microunit", -1)
        selection = div_half_up(850_000 * base + 150_000 * novelty, scale)
        report.require(expected == {"base_microunit": base, "novelty_microunit": novelty, "selection_score_microunit": selection}, code, f"{vector_id} recommendation arithmetic mismatch")

    tie = by_id.get("GV-TIE-001", {})
    candidates = tie.get("input", {}).get("candidates", [])
    ordered = sorted(candidates, key=lambda item: (-item["selection_score_microunit"], -item["base_microunit"], item["duration_minutes"], item["content_id"].encode("utf-8"))) if all(isinstance(item, dict) for item in candidates) else []
    report.require(tie.get("expected", {}).get("ordered_content_ids") == [item.get("content_id") for item in ordered], code, "recommendation tie-break vector mismatch")

    decision_contract = vectors.get("decision_contract", {})
    expected_boundaries = [
        {"level": "L1", "minimum_score_microunit": 0, "maximum_score_microunit": 24_999_999},
        {"level": "L2", "minimum_score_microunit": 25_000_000, "maximum_score_microunit": 49_999_999},
        {"level": "L3", "minimum_score_microunit": 50_000_000, "maximum_score_microunit": 74_999_999},
        {"level": "L4", "minimum_score_microunit": 75_000_000, "maximum_score_microunit": 100_000_000},
    ]
    report.require(decision_contract.get("policy_version") == "diagnosis-decision.v1" and decision_contract.get("score_range_microunit") == [0, 100_000_000], code, "diagnosis decision identity/range drift")
    report.require(
        decision_contract.get("invalid_evidence_rule")
        == "INVALID_EVIDENCE is evaluated first when score is outside 0..100000000, confidence/conflict is outside 0..1000000, a numeric field is bool/non-integer, or required_indicators_satisfied is non-boolean",
        code,
        "INVALID_EVIDENCE first-precedence predicate drift",
    )
    report.require(decision_contract.get("level_boundaries") == expected_boundaries, code, "L1-L4 inclusive score boundaries drift")
    report.require(decision_contract.get("confidence_threshold_microunit") == 600_000, code, "confidence threshold drift")
    report.require(decision_contract.get("conflict_threshold_microunit") == 500_000, code, "conflict threshold drift")
    report.require(decision_contract.get("required_indicator_minimum_distinct_turns") == 2 and decision_contract.get("required_indicator_minimum_confidence_microunit") == 600_000, code, "required-indicator coverage contract drift")
    report.require(
        decision_contract.get("dimension_confidence_formula") == "div_half_up(sum(indicator_weight_microunit * confidence_microunit), sum(indicator_weight_microunit))"
        and decision_contract.get("overall_confidence_formula") == "div_half_up(sum(dimension_weight_microunit * dimension_confidence_microunit), sum(dimension_weight_microunit))",
        code,
        "confidence formula drift",
    )
    report.require(
        decision_contract.get("conflict_formula") == "max(div_half_up(SCALE * abs(anchor_a - anchor_b), anchor_count - 1)) for selected evidence pairs on the same indicator with distinct turn_sequence and confidence >= 600000",
        code,
        "conflict formula drift",
    )
    report.require(decision_contract.get("result_precedence") == ["INVALID_EVIDENCE", "INSUFFICIENT_EVIDENCE", "HUMAN_REVIEW_REQUIRED", "ADDITIONAL_CONFIRMATION_REQUIRED", "LEVEL_ASSIGNED"], code, "diagnosis result precedence drift")
    report.require(decision_contract.get("next_question_order") == ["required_indicator_satisfied=false", "coverage_count ascending", "rubric_priority ascending", "question_id NFC UTF-8 bytewise ascending"], code, "next-question ordering drift")

    expected_decision_ids = [
        "GV-LEVEL-L1-MIN", "GV-LEVEL-L1-MAX", "GV-LEVEL-L2-MIN", "GV-LEVEL-L2-MAX", "GV-LEVEL-L3-MIN", "GV-LEVEL-L3-MAX", "GV-LEVEL-L4-MIN", "GV-LEVEL-L4-MAX",
        "GV-CONFIDENCE-BELOW", "GV-CONFIDENCE-AT", "GV-CONFLICT-BELOW", "GV-CONFLICT-AT",
        "GV-INVALID-BELOW-RANGE", "GV-INVALID-ABOVE-RANGE", "GV-INVALID-WITH-INSUFFICIENT", "GV-INVALID-WITH-CONFLICT", "GV-INVALID-WITH-LOW-CONFIDENCE",
        "GV-REQUIRED-COVERAGE-ONE", "GV-REQUIRED-COVERAGE-TWO", "GV-NEXT-QUESTION-ORDER",
    ]
    decision_rows = vectors.get("decision_vectors", [])
    decision_by_id = {row.get("id"): row for row in decision_rows if isinstance(row, dict)}
    report.require([row.get("id") for row in decision_rows if isinstance(row, dict)] == expected_decision_ids, code, "decision boundary vector IDs/order drift")

    def decision_result(source: dict[str, Any]) -> dict[str, Any]:
        score = source.get("overall_score_microunit")
        confidence = source.get("overall_confidence_microunit")
        conflict = source.get("conflict_microunit")
        required_satisfied = source.get("required_indicators_satisfied")
        if (
            not isinstance(score, int) or isinstance(score, bool) or not 0 <= score <= 100_000_000
            or not isinstance(confidence, int) or isinstance(confidence, bool) or not 0 <= confidence <= 1_000_000
            or not isinstance(conflict, int) or isinstance(conflict, bool) or not 0 <= conflict <= 1_000_000
            or not isinstance(required_satisfied, bool)
        ):
            return {"status": "INVALID_EVIDENCE", "level": None}
        if required_satisfied is False:
            return {"status": "INSUFFICIENT_EVIDENCE", "level": None}
        if conflict >= 500_000:
            return {"status": "HUMAN_REVIEW_REQUIRED", "level": None}
        if confidence < 600_000:
            return {"status": "ADDITIONAL_CONFIRMATION_REQUIRED", "level": None}
        for boundary in expected_boundaries:
            if boundary["minimum_score_microunit"] <= score <= boundary["maximum_score_microunit"]:
                return {"status": "LEVEL_ASSIGNED", "level": boundary["level"]}
        return {"status": "INVALID_EVIDENCE", "level": None}

    executable_decision_ids = expected_decision_ids[:-3]
    for vector_id in executable_decision_ids:
        row = decision_by_id.get(vector_id, {})
        try:
            actual = decision_result(row.get("input", {}))
        except TypeError as exc:
            report.require(False, code, f"{vector_id} decision input invalid: {exc}")
            continue
        report.require(actual == row.get("expected"), code, f"{vector_id} boundary decision mismatch")
    for vector_id in ("GV-REQUIRED-COVERAGE-ONE", "GV-REQUIRED-COVERAGE-TWO"):
        row = decision_by_id.get(vector_id, {})
        source = row.get("input", {})
        sequences = source.get("coverage_turn_sequences", [])
        confidences = source.get("confidence_microunit", [])
        qualified = {sequence for sequence, confidence in zip(sequences, confidences) if isinstance(confidence, int) and confidence >= 600_000}
        actual = {"required_indicator_satisfied": len(qualified) >= 2, "coverage_count": len(qualified)}
        report.require(actual == row.get("expected"), code, f"{vector_id} required-indicator coverage mismatch")
    question_row = decision_by_id.get("GV-NEXT-QUESTION-ORDER", {})
    question_candidates = question_row.get("input", {}).get("candidates", [])
    question_order = sorted(question_candidates, key=lambda item: (item["required_indicator_satisfied"], item["coverage_count"], item["rubric_priority"], item["question_id"].encode("utf-8"))) if all(isinstance(item, dict) for item in question_candidates) else []
    report.require(bool(question_order) and question_row.get("expected", {}).get("selected_question_id") == question_order[0].get("question_id"), code, "next-question boundary vector mismatch")
    report.pass_group(code, "scoring, level/confidence/conflict/coverage boundaries, persona, recommendation, and tie vectors are executable", before)


def verify_ai_gateway_schema(schema: dict[str, Any], package_root: Path, report: Report) -> None:
    before = len(report.failures)
    code = "AI_GATEWAY_WIRE"
    report.require(schema.get("$id") == "urn:yonlab:canonical-ai-request-envelope:1.0.0", code, "canonical AI request schema ID drift")
    report.require(schema.get("type") == "object" and schema.get("additionalProperties") is False and schema.get("required") == ["headers", "body"], code, "canonical envelope root drift")
    definitions = schema.get("$defs", {})
    headers = definitions.get("headers", {})
    body = definitions.get("body", {})
    policy = definitions.get("policyVersions", {})
    expected_headers = ["content_type", "idempotency_key", "x_request_id", "traceparent", "workload_spiffe_id"]
    expected_body = ["task", "tenant_id", "input", "response_schema_id", "policy_versions", "latency_budget_ms", "data_use_context"]
    expected_policies = ["routing", "prompt", "model_registry", "schema_registry", "data_use", "consent_authorization", "tenant_isolation", "safeguarding_routing"]
    report.require(headers.get("type") == "object" and headers.get("additionalProperties") is False and headers.get("required") == expected_headers, code, "canonical HTTP header contract drift")
    report.require(body.get("type") == "object" and body.get("additionalProperties") is False and body.get("required") == expected_body, code, "canonical body field contract drift")
    report.require(set(body.get("properties", {})) == set(expected_body), code, "canonical body properties must be exact")
    report.require(policy.get("type") == "object" and policy.get("additionalProperties") is False and policy.get("required") == expected_policies and set(policy.get("properties", {})) == set(expected_policies), code, "canonical policy_versions contract drift")
    report.require(definitions.get("dataUseContext", {}).get("required") == ["payload", "signature", "canonicalization"], code, "signed DataUseContext envelope drift")
    report.require(
        definitions.get("dataUsePayload", {}).get("properties", {}).get("consent_basis", {}).get("enum")
        == ["CONSENT", "CONTRACT", "LEGAL_OBLIGATION", "PUBLIC_TASK", "PUBLICATION_RIGHTS"],
        code,
        "PUBLICATION_RIGHTS consent basis required by the normative public-document flow is missing",
    )
    safeguarding_decisions = [
        "STANDARD",
        "CHILD_SAFEGUARDING",
        "IMMINENT_DANGER",
        "SECURITY_EXFILTRATION",
        "POLICY_BLOCK",
    ]
    report.require(
        definitions.get("dataUsePayload", {}).get("properties", {}).get("safeguarding_decision", {}).get("enum")
        == safeguarding_decisions,
        code,
        "safeguarding_decision must use the exact five-state fail-closed vocabulary",
    )
    safeguarding_vectors = load_json(package_root / "fixtures/ai-gateway-safeguarding-decision-vectors.json", report)
    if isinstance(safeguarding_vectors, dict):
        positive_cases = safeguarding_vectors.get("positive_cases", [])
        negative_cases = safeguarding_vectors.get("negative_cases", [])
        report.require(
            safeguarding_vectors.get("schema_version") == "ai-gateway-safeguarding-decision-v1"
            and safeguarding_vectors.get("canonical_decisions") == safeguarding_decisions
            and [row.get("decision") for row in positive_cases if isinstance(row, dict)] == safeguarding_decisions
            and all(row.get("expected_schema_valid") is True for row in positive_cases if isinstance(row, dict))
            and len(negative_cases) == 1
            and isinstance(negative_cases[0], dict)
            and negative_cases[0].get("decision") == "UNKNOWN"
            and negative_cases[0].get("expected_schema_valid") is False
            and negative_cases[0].get("expected_fail_closed_decision") == "POLICY_BLOCK",
            code,
            "safeguarding positive/unknown-negative vector coverage drift",
        )
    wire = schema.get("x-wire-contract", {})
    report.require(
        wire.get("endpoint") == "POST /internal/ai/v1/responses"
        and wire.get("body_unknown_properties") == "REJECT"
        and wire.get("provider_fields") == "FORBIDDEN"
        and wire.get("idempotency_and_trace_fields_are_headers_only") is True,
        code,
        "AI Gateway endpoint/unknown/provider/header-only policy drift",
    )
    signed_binding = schema.get("x-signed-binding-contract", {})
    expected_policy_mapping = {
        "data_use": "DataUsePolicyVersion",
        "consent_authorization": "ConsentAuthorizationPolicyVersion",
        "tenant_isolation": "TenantIsolationPolicyVersion",
        "safeguarding_routing": "SafeguardingRoutingPolicyVersion",
    }
    report.require(
        signed_binding
        == {
            "input_digest_projection": "body.input",
            "input_digest_canonicalization": "RFC8785-JCS",
            "input_digest_algorithm": "SHA-256",
            "input_digest_target": "body.data_use_context.payload.payload_sha256",
            "body_payload_equal_fields": ["task", "tenant_id"],
            "body_payload_policy_mapping": expected_policy_mapping,
            "mismatch_result": "POLICY_VERSION_MISMATCH_OR_DATA_USE_CONTEXT_INVALID",
        },
        code,
        "AI request signed input/task/tenant/policy binding contract drift",
    )
    valid = load_json(package_root / "fixtures/ai-gateway-request.valid.json", report)
    if isinstance(valid, dict):
        errors = validate_instance(schema, valid, schema)
        report.require(not errors, code, f"canonical AI request fixture failed schema validation: {errors[:3]}")
        valid_headers = valid.get("headers", {})
        valid_body = valid.get("body", {})
        payload = valid_body.get("data_use_context", {}).get("payload", {}) if isinstance(valid_body, dict) else {}
        report.require(valid_body.get("task") == payload.get("task") and valid_body.get("tenant_id") == payload.get("tenant_id"), code, "signed payload task/tenant must equal body task/tenant")
        try:
            input_digest = hashlib.sha256(canonical_json(valid_body.get("input")).encode("utf-8")).hexdigest()
        except ValueError as exc:
            report.require(False, code, f"canonical request input is outside the JCS contract subset: {exc}")
            input_digest = ""
        report.require(
            payload.get("payload_sha256") == input_digest,
            code,
            "payload_sha256 must equal SHA-256(UTF-8(JCS(body.input)))",
        )
        body_policies = valid_body.get("policy_versions", {})
        payload_policies = payload.get("policy_versions", {}) if isinstance(payload, dict) else {}
        report.require(
            all(body_policies.get(body_key) == payload_policies.get(payload_key) for body_key, payload_key in expected_policy_mapping.items()),
            code,
            "signed payload policy versions must equal their canonical body policy versions",
        )
        report.require(not ({"idempotency_key", "trace_id", "provider", "provider_model", "credential"} & set(valid_body)), code, "headers/provider fields leaked into canonical body")
        try:
            issued = datetime.fromisoformat(str(payload.get("issued_at", "")).replace("Z", "+00:00"))
            expires = datetime.fromisoformat(str(payload.get("expires_at", "")).replace("Z", "+00:00"))
            report.require(0 < (expires - issued).total_seconds() <= 60, code, "DataUseContext lifetime must be 1..60 seconds")
        except ValueError:
            report.require(False, code, "DataUseContext timestamps are invalid")
        report.require(valid_headers.get("content_type") == "application/json", code, "canonical content type drift")
    report.pass_group(code, "canonical headers/body/policy versions and signed context are exact and provider-neutral", before)


def verify_hwp_boundary(contract: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "HWP_BOUNDARY"
    try:
        digest = hashlib.sha256(canonical_json(contract).encode("utf-8")).hexdigest()
    except ValueError as exc:
        report.require(False, code, f"HWP boundary contract is outside the canonical subset: {exc}")
        digest = ""
    report.require(
        digest == HWP_BOUNDARY_CONTRACT_SHA256,
        code,
        "HWP queue/job/IPC/sandbox/attestation contract digest drift",
    )
    report.require(
        contract.get("schema_version") == "hwp-conversion-boundary.v1"
        and contract.get("contract_state") == "BLOCKED_UNTIL_PRODUCTION_CONVERTER_AND_GOLDEN_CORPUS_EVIDENCE",
        code,
        "HWP contract identity or fail-closed release state drift",
    )
    bridge = contract.get("bridge_host", {})
    queue = bridge.get("queue", {}) if isinstance(bridge, dict) else {}
    report.require(
        bridge.get("workload_identity") == "SPIFFE_X509_SVID_REQUIRED"
        and bridge.get("public_ingress") == "DENY"
        and bridge.get("database_credentials") == "NONE"
        and queue
        == {
            "queue_name": "document.hwp.convert.v1",
            "delivery": "AT_LEAST_ONCE",
            "deduplication_key": "job_id",
            "acknowledgement": "AFTER_OUTPUT_ATTESTATION_AND_OBJECT_COMMIT",
            "dead_letter_policy": "FAIL_CLOSED_AFTER_3_ATTEMPTS",
        },
        code,
        "HWP bridge identity/queue commit semantics drift",
    )
    job = contract.get("job_envelope", {})
    report.require(
        job.get("schema_id") == "urn:yonlab:hwp-conversion-job:1.0.0"
        and job.get("additional_properties") == "REJECT"
        and job.get("raw_document_bytes_in_queue") == "FORBIDDEN"
        and job.get("maximum_lifetime_seconds") == 300
        and len(job.get("required_fields", [])) == 12,
        code,
        "HWP job envelope/expiry/raw-byte policy drift",
    )
    ipc = contract.get("bridge_child_ipc", {})
    report.require(
        ipc.get("transport") == "HOST_LOCAL_NAMED_PIPE_OR_VSOCK"
        and ipc.get("network_socket") == "FORBIDDEN"
        and ipc.get("protocol") == "LENGTH_PREFIXED_CANONICAL_CBOR_V1"
        and ipc.get("reject_absolute_or_parent_paths") is True,
        code,
        "HWP host-child IPC/path contract drift",
    )
    child = contract.get("child_sandbox", {})
    report.require(
        child.get("network") == "NONE"
        and child.get("credentials") == "NONE"
        and child.get("environment_secret_allowlist") == []
        and all(child.get(field) == "NONE" for field in ("database_access", "queue_access", "object_storage_access", "telemetry_access")),
        code,
        "HWP child must have zero network, credential, DB, queue, object, and telemetry access",
    )
    filesystem = child.get("filesystem", {}) if isinstance(child, dict) else {}
    isolation = child.get("isolation", {}) if isinstance(child, dict) else {}
    report.require(
        filesystem.get("binary_mount") == "READ_ONLY"
        and filesystem.get("input_mount") == "READ_ONLY_SINGLE_FILE"
        and filesystem.get("output_mount") == "WRITE_ONLY_EMPTY_DIRECTORY"
        and filesystem.get("host_paths") == "DENY"
        and isolation.get("capabilities") == "DROP_ALL"
        and isolation.get("privilege_escalation") == "DENY"
        and isolation.get("macro_script_execution") == "DENY",
        code,
        "HWP child filesystem/process isolation drift",
    )
    attestation = contract.get("output_attestation", {})
    report.require(
        attestation.get("schema_id") == "urn:yonlab:hwp-conversion-attestation:1.0.0"
        and attestation.get("additional_properties") == "REJECT"
        and attestation.get("signature") == "ED25519_DETACHED_OVER_RFC8785_JCS_UNSIGNED_ATTESTATION"
        and len(attestation.get("required_fields", [])) == 17
        and len(attestation.get("acceptance_predicates", [])) == 7,
        code,
        "HWP output byte/digest/image/policy/evidence/signature attestation drift",
    )
    report.require(
        contract.get("failure_policy", {}).get("converter_or_golden_evidence_missing") == "RELEASE_BLOCKED"
        and contract.get("failure_policy", {}).get("simulator_evidence") == "NEVER_COUNTS_AS_PRODUCTION_ACCEPTANCE",
        code,
        "HWP missing-real-converter/simulator evidence policy drift",
    )
    report.pass_group(code, f"exact queue/job/IPC/child/attestation contract reproduces {HWP_BOUNDARY_CONTRACT_SHA256}", before)


def verify_source_tree_vector(source: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "SOURCE_TREE_GOLDEN"
    rows = source.get("vectors", [])
    report.require(source.get("schema_version") == "source-tree-hash-golden.v1" and len(rows) == 1, code, "source-tree vector identity/count drift")
    if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
        return
    row = rows[0]
    fixture_files = row.get("fixture_files", [])
    records: list[dict[str, Any]] = []
    for fixture in fixture_files:
        if not isinstance(fixture, dict):
            report.require(False, code, "fixture file must be an object")
            continue
        path = fixture.get("path")
        content = fixture.get("content_utf8")
        mode = fixture.get("mode")
        valid_path = is_nonempty_string(path) and unicodedata.normalize("NFC", path) == path and not path.startswith("/") and "\\" not in path and "%" not in path and all(part not in ("", ".", "..") for part in path.split("/"))
        report.require(valid_path, code, f"unsafe/non-NFC source-tree fixture path: {path!r}")
        report.require(mode in ("100644", "100755"), code, f"invalid source-tree mode: {mode!r}")
        if not isinstance(content, str):
            report.require(False, code, f"fixture content is not UTF-8 text: {path}")
            continue
        payload = content.encode("utf-8")
        digest = hashlib.sha256(payload).hexdigest()
        report.require(fixture.get("size_bytes") == len(payload), code, f"fixture size mismatch: {path}")
        report.require(fixture.get("content_sha256") == digest, code, f"fixture content digest mismatch: {path}")
        records.append({"content_sha256": digest, "mode": mode, "path": path, "size_bytes": len(payload)})
    records.sort(key=lambda item: unicodedata.normalize("NFC", item["path"]).encode("utf-8"))
    manifest = {"files": records, "schema": "source-tree-manifest.v1"}
    canonical = canonical_json(manifest)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    report.require(row.get("id") == "GV-SOURCE-TREE-001", code, "source-tree vector ID drift")
    report.require(row.get("canonical_manifest_utf8") == canonical, code, "canonical source-tree manifest bytes drift")
    report.require(row.get("canonical_digest_sha256") == digest == source.get("canonical_digest_sha256"), code, "canonical source-tree SHA-256 drift")
    report.pass_group(code, f"RFC 8785 subset bytes reproduce {digest}", before)


def verify_final_document_inventory(inventory: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "FINAL_INVENTORY_DIGEST"
    contract = inventory.get("canonical_contract", {})
    artifacts = inventory.get("artifacts", [])
    expected_counts = {
        "design": 48,
        "operations": 11,
        "runbook": 23,
        "qa": 18,
        "manual_markdown": 8,
        "manual_pdf": 8,
        "release": 10,
        "distribution": 21,
        "total": 147,
    }
    actual_counts = Counter(item.get("group") for item in artifacts if isinstance(item, dict))
    report.require(
        isinstance(artifacts, list)
        and len(artifacts) == 147
        and inventory.get("expected_counts") == expected_counts
        and all(actual_counts[group] == count for group, count in expected_counts.items() if group != "total"),
        code,
        "final document inventory must close exact total=147, design=48 and all group counts",
    )
    report.require(
        contract
        == {
            "algorithm": "SHA-256",
            "serialization": "RFC8785-compatible integer/string subset: UTF-8, lexicographically sorted object keys, no insignificant whitespace, unescaped Unicode",
            "projection": "The entire JSON object with the top-level canonical_contract member omitted",
            "digest_sha256": FINAL_DOCUMENT_INVENTORY_SHA256,
        },
        code,
        "final document canonical serialization/digest contract drift",
    )
    projection = dict(inventory)
    projection.pop("canonical_contract", None)
    try:
        canonical = canonical_json(projection)
        digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    except ValueError as exc:
        report.require(False, code, f"final document inventory is outside the canonical subset: {exc}")
        digest = ""
    report.require(
        digest == contract.get("digest_sha256") == FINAL_DOCUMENT_INVENTORY_SHA256,
        code,
        "final document inventory canonical bytes do not match the externally pinned digest",
    )
    report.pass_group(code, f"147 exact final-document paths reproduce {FINAL_DOCUMENT_INVENTORY_SHA256}", before)


def verify_document_graph_schema(schema: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "DOCUMENT_GRAPH_SCHEMA"
    expected_root_required = [
        "schema_id",
        "schema_version",
        "locator_policy_version",
        "tenant_id",
        "document_id",
        "document_version_id",
        "source_format",
        "source_sha256",
        "converter_artifact",
        "root_node_id",
        "nodes",
        "validation",
    ]
    report.require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", code, "DocumentGraph must declare Draft 2020-12")
    report.require(schema.get("$id") == "urn:yonlab:document-graph:1.0.0", code, "DocumentGraph $id drift")
    report.require(schema.get("type") == "object" and schema.get("additionalProperties") is False, code, "DocumentGraph root must be a closed object")
    report.require(schema.get("required") == expected_root_required, code, "DocumentGraph root required fields/order drift")
    properties = schema.get("properties", {})
    report.require(properties.get("schema_id", {}).get("const") == "urn:yonlab:document-graph:1.0.0", code, "DocumentGraph schema_id drift")
    report.require(properties.get("schema_version", {}).get("const") == "document-graph.v1", code, "DocumentGraph schema_version drift")
    report.require(properties.get("locator_policy_version", {}).get("const") == "source-locator.v1", code, "DocumentGraph locator policy drift")
    report.require(properties.get("source_format", {}).get("enum") == ["HWPX", "PDF", "IMAGE", "DOCX"], code, "DocumentGraph source format vocabulary drift")
    report.require(properties.get("nodes") == {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/node"}}, code, "DocumentGraph nodes collection contract drift")

    definitions = schema.get("$defs", {})
    bbox = definitions.get("normalizedBoundingBox", {})
    expected_bbox_required = ["x0_microunit", "y0_microunit", "x1_microunit", "y1_microunit"]
    report.require(bbox.get("type") == "object" and bbox.get("additionalProperties") is False, code, "normalizedBoundingBox must be closed")
    report.require(bbox.get("required") == expected_bbox_required, code, "normalizedBoundingBox required fields drift")
    bbox_properties = bbox.get("properties", {})
    for coordinate in expected_bbox_required:
        report.require(
            bbox_properties.get(coordinate) == {"type": "integer", "minimum": 0, "maximum": 1_000_000},
            code,
            f"normalizedBoundingBox.{coordinate} must be integer micro-units in [0,1000000]",
        )
    report.require(
        definitions.get("sourceLocator", {}).get("oneOf")
        == [
            {"$ref": "#/$defs/hwpxLocator"},
            {"$ref": "#/$defs/pageLocator"},
            {"$ref": "#/$defs/tableLocator"},
        ],
        code,
        "sourceLocator union drift",
    )
    table = definitions.get("tableData", {})
    report.require(
        table.get("additionalProperties") is False
        and table.get("required") == ["row_count", "column_count"]
        and table.get("properties", {}).get("row_count") == {"type": "integer", "minimum": 1}
        and table.get("properties", {}).get("column_count") == {"type": "integer", "minimum": 1},
        code,
        "table topology core contract drift",
    )
    cell = definitions.get("cellData", {})
    report.require(
        cell.get("additionalProperties") is False
        and cell.get("required")
        == ["table_node_id", "row_start", "row_end", "column_start", "column_end", "header_scope", "nested_table_ids"]
        and cell.get("properties", {}).get("header_scope", {}).get("enum") == ["NONE", "ROW", "COLUMN", "BOTH"]
        and cell.get("properties", {}).get("nested_table_ids", {}).get("uniqueItems") is True,
        code,
        "cell topology core contract drift",
    )
    node = definitions.get("node", {})
    report.require(
        node.get("additionalProperties") is False
        and node.get("required")
        == ["node_id", "parent_id", "order", "type", "text", "style_ref", "source_locator", "confidence_ppm", "children", "provenance"],
        code,
        "DocumentGraph node required/closed contract drift",
    )
    report.require(
        node.get("properties", {}).get("confidence_ppm") == {"type": "integer", "minimum": 0, "maximum": 1_000_000},
        code,
        "node confidence micro-unit bounds drift",
    )
    report.require(len(node.get("allOf", [])) == 2, code, "TABLE/CELL conditional topology rules are missing")
    semantic = schema.get("x-semantic-contract", {})
    report.require(
        semantic.get("canonicalization") == "RFC8785-compatible JCS integer/string subset"
        and semantic.get("uuid_v5_namespace") == "document_version_id UUID bytes"
        and semantic.get("uuid_v5_name") == "UTF-8('document-graph.v1' || 0x0A || node.type || 0x0A || base10(node.order) || 0x0A) || UTF-8(JCS(source_locator))",
        code,
        "DocumentGraph UUIDv5 semantic contract drift",
    )
    report.require(
        semantic.get("topology")
        == [
            "one root matching root_node_id",
            "connected acyclic parent/children inverse edges",
            "nodes array root-first preorder",
            "sibling order is contiguous 0..n-1",
            "every CELL nested_table_ids member resolves to a TABLE descendant whose nearest CELL ancestor is that CELL",
            "nested-table annotation edges are complete and acyclic",
        ]
        and semantic.get("ranges")
        == [
            "text start <= end",
            "bbox x0 < x1 and y0 < y1",
            "table/cell half-open start < end within table bounds",
            "CELL source locator equals cell topology",
            "CELL rectangles cover every table grid coordinate exactly once; merged rectangles are allowed but overlaps and gaps are forbidden",
        ],
        code,
        "DocumentGraph nested-table and exact cell-coverage semantic rules drift",
    )
    fixture_contract = semantic.get("fixtures", {})
    report.require(
        fixture_contract.get("valid") == "fixtures/document-graph.valid.json"
        and fixture_contract.get("invalid")
        == [
            {"path": "fixtures/document-graph.invalid-topology.json", "error_code": "TOPOLOGY"},
            {"path": "fixtures/document-graph.invalid-uuid.json", "error_code": "UUIDV5"},
            {"path": "fixtures/document-graph.invalid-range.json", "error_code": "RANGE"},
            {"path": "fixtures/document-graph.invalid-nested-dangling.json", "error_code": "NESTED_TABLE_REFERENCE"},
            {"path": "fixtures/document-graph.invalid-nested-cycle.json", "error_code": "NESTED_TABLE_CYCLE"},
            {"path": "fixtures/document-graph.invalid-cell-overlap.json", "error_code": "CELL_COVERAGE"},
            {"path": "fixtures/document-graph.invalid-cell-gap.json", "error_code": "CELL_COVERAGE"},
        ],
        code,
        "DocumentGraph semantic fixture inventory drift",
    )
    report.pass_group(code, "DocumentGraph identity, locator union, topology, UUID references, and micro-unit bounds are pinned", before)


def document_graph_semantic_errors(graph: dict[str, Any], schema: dict[str, Any]) -> set[str]:
    errors: set[str] = set()
    if validate_instance(schema, graph, schema):
        errors.add("SCHEMA")
    rows = graph.get("nodes", [])
    if not isinstance(rows, list) or not rows or not all(isinstance(row, dict) for row in rows):
        return errors | {"TOPOLOGY"}
    by_id = {row.get("node_id"): row for row in rows}
    if len(by_id) != len(rows) or None in by_id:
        errors.add("TOPOLOGY")
    root_id = graph.get("root_node_id")
    root = by_id.get(root_id)
    roots = [row for row in rows if row.get("parent_id") is None]
    if root is None or len(roots) != 1 or roots[0].get("node_id") != root_id or root.get("order") != 0:
        errors.add("TOPOLOGY")

    for row in rows:
        node_id = row.get("node_id")
        parent_id = row.get("parent_id")
        children = row.get("children", [])
        if not isinstance(children, list) or len(children) != len(set(children)):
            errors.add("TOPOLOGY")
            continue
        if parent_id is not None:
            parent = by_id.get(parent_id)
            if parent is None or node_id not in parent.get("children", []):
                errors.add("TOPOLOGY")
        for index, child_id in enumerate(children):
            child = by_id.get(child_id)
            if child is None or child.get("parent_id") != node_id or child.get("order") != index:
                errors.add("TOPOLOGY")
        if unicodedata.normalize("NFC", str(row.get("text", ""))) != row.get("text"):
            errors.add("RANGE")
        try:
            namespace = uuid.UUID(str(graph.get("document_version_id")))
            name = f"document-graph.v1\n{row.get('type')}\n{row.get('order')}\n{canonical_json(row.get('source_locator'))}"
            if str(uuid.uuid5(namespace, name)) != node_id:
                errors.add("UUIDV5")
        except (ValueError, TypeError):
            errors.add("UUIDV5")

    preorder: list[str] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def walk(node_id: str) -> None:
        if node_id in visiting:
            errors.add("TOPOLOGY")
            return
        if node_id in visited:
            errors.add("TOPOLOGY")
            return
        node = by_id.get(node_id)
        if node is None:
            errors.add("TOPOLOGY")
            return
        visiting.add(node_id)
        visited.add(node_id)
        preorder.append(node_id)
        for child_id in node.get("children", []):
            walk(child_id)
        visiting.remove(node_id)

    if isinstance(root_id, str):
        walk(root_id)
    if preorder != [row.get("node_id") for row in rows] or len(visited) != len(rows):
        errors.add("TOPOLOGY")

    tables = {row.get("node_id"): row for row in rows if row.get("type") == "TABLE"}

    def ancestors(node_id: str) -> list[str]:
        result: list[str] = []
        seen: set[str] = set()
        current = by_id.get(node_id, {}).get("parent_id")
        while isinstance(current, str) and current not in seen:
            seen.add(current)
            result.append(current)
            current = by_id.get(current, {}).get("parent_id")
        return result

    def nearest_cell_ancestor(node_id: str) -> str | None:
        for ancestor_id in ancestors(node_id):
            if by_id.get(ancestor_id, {}).get("type") == "CELL":
                return ancestor_id
        return None

    nested_edges: dict[str, set[str]] = {table_id: set() for table_id in tables}

    def check_locator(locator: Any) -> None:
        if not isinstance(locator, dict):
            errors.add("RANGE")
            return
        text_range = locator.get("text_range")
        if isinstance(text_range, dict) and text_range.get("start_codepoint", 0) > text_range.get("end_codepoint", -1):
            errors.add("RANGE")
        bbox = locator.get("bbox")
        if isinstance(bbox, dict) and not (bbox.get("x0_microunit", 0) < bbox.get("x1_microunit", 0) and bbox.get("y0_microunit", 0) < bbox.get("y1_microunit", 0)):
            errors.add("RANGE")
        if locator.get("locator_type") == "TABLE":
            if not (locator.get("row_start", 0) < locator.get("row_end", 0) and locator.get("column_start", 0) < locator.get("column_end", 0)):
                errors.add("RANGE")
            table = tables.get(locator.get("table_node_id"))
            table_data = table.get("table", {}) if isinstance(table, dict) else {}
            if table is None or locator.get("row_end", 0) > table_data.get("row_count", 0) or locator.get("column_end", 0) > table_data.get("column_count", 0):
                errors.add("RANGE")
            check_locator(locator.get("source_anchor"))

    for row in rows:
        check_locator(row.get("source_locator"))
        if row.get("type") == "CELL":
            cell = row.get("cell", {})
            locator = row.get("source_locator", {})
            if not isinstance(cell, dict) or not (
                cell.get("row_start", 0) < cell.get("row_end", 0)
                and cell.get("column_start", 0) < cell.get("column_end", 0)
            ):
                errors.add("RANGE")
            table = tables.get(cell.get("table_node_id")) if isinstance(cell, dict) else None
            table_data = table.get("table", {}) if isinstance(table, dict) else {}
            if table is None or cell.get("row_end", 0) > table_data.get("row_count", 0) or cell.get("column_end", 0) > table_data.get("column_count", 0):
                errors.add("RANGE")
            comparable = ("table_node_id", "row_start", "row_end", "column_start", "column_end")
            if not isinstance(locator, dict) or locator.get("locator_type") != "TABLE" or any(cell.get(key) != locator.get(key) for key in comparable):
                errors.add("RANGE")
            nested_ids = cell.get("nested_table_ids", []) if isinstance(cell, dict) else []
            expected_nested_ids = {
                table_id
                for table_id in tables
                if nearest_cell_ancestor(str(table_id)) == row.get("node_id")
            }
            if not isinstance(nested_ids, list):
                errors.add("NESTED_TABLE_REFERENCE")
                nested_ids = []
            for nested_id in nested_ids:
                nested = tables.get(nested_id)
                if nested is None:
                    errors.add("NESTED_TABLE_REFERENCE")
                elif nested_id in ancestors(str(row.get("node_id"))):
                    errors.add("NESTED_TABLE_CYCLE")
                elif nearest_cell_ancestor(str(nested_id)) != row.get("node_id"):
                    errors.add("NESTED_TABLE_REFERENCE")
                containing_table_id = cell.get("table_node_id") if isinstance(cell, dict) else None
                if containing_table_id in nested_edges and nested_id in tables:
                    nested_edges[containing_table_id].add(nested_id)
            if set(nested_ids) != expected_nested_ids:
                errors.add("NESTED_TABLE_REFERENCE")

    nested_visiting: set[str] = set()
    nested_visited: set[str] = set()

    def walk_nested(table_id: str) -> None:
        if table_id in nested_visiting:
            errors.add("NESTED_TABLE_CYCLE")
            return
        if table_id in nested_visited:
            return
        nested_visiting.add(table_id)
        for child_table_id in nested_edges.get(table_id, set()):
            walk_nested(child_table_id)
        nested_visiting.remove(table_id)
        nested_visited.add(table_id)

    for table_id in tables:
        walk_nested(str(table_id))

    for table_id, table in tables.items():
        table_data = table.get("table", {}) if isinstance(table, dict) else {}
        row_count = table_data.get("row_count")
        column_count = table_data.get("column_count")
        if not isinstance(row_count, int) or not isinstance(column_count, int):
            errors.add("CELL_COVERAGE")
            continue
        coverage = [[0 for _ in range(column_count)] for _ in range(row_count)]
        table_cells = [
            row
            for row in rows
            if row.get("type") == "CELL" and row.get("cell", {}).get("table_node_id") == table_id
        ]
        for cell_row in table_cells:
            cell = cell_row.get("cell", {})
            for row_index in range(max(0, cell.get("row_start", 0)), min(row_count, cell.get("row_end", 0))):
                for column_index in range(max(0, cell.get("column_start", 0)), min(column_count, cell.get("column_end", 0))):
                    coverage[row_index][column_index] += 1
        if any(count != 1 for coverage_row in coverage for count in coverage_row):
            errors.add("CELL_COVERAGE")
    return errors


def verify_document_graph_fixtures(package_root: Path, schema: dict[str, Any], report: Report) -> None:
    before = len(report.failures)
    code = "DOCUMENT_GRAPH_SEMANTICS"
    contract = schema.get("x-semantic-contract", {}).get("fixtures", {})
    valid = load_json(package_root / str(contract.get("valid", "")), report)
    if isinstance(valid, dict):
        report.require(not document_graph_semantic_errors(valid, schema), code, f"valid DocumentGraph fixture failed: {sorted(document_graph_semantic_errors(valid, schema))}")
    for row in contract.get("invalid", []) if isinstance(contract.get("invalid", []), list) else []:
        if not isinstance(row, dict):
            report.require(False, code, "invalid DocumentGraph fixture row must be an object")
            continue
        fixture = load_json(package_root / str(row.get("path", "")), report)
        if isinstance(fixture, dict):
            actual = document_graph_semantic_errors(fixture, schema)
            report.require(row.get("error_code") in actual, code, f"{row.get('path')} did not fail with {row.get('error_code')}: {sorted(actual)}")
    report.pass_group(code, "schema-valid merged/nested graph plus topology, UUIDv5, locator, nested-table, overlap and gap negatives are enforced", before)


def verify_release_schema_cores(
    artifact_schema: dict[str, Any],
    evidence_schema: dict[str, Any],
    report: Report,
) -> None:
    before = len(report.failures)
    code = "RELEASE_SCHEMA_CORE"
    artifact_required = [
        "schema_version",
        "release",
        "release_state",
        "scope",
        "source_release_manifest_sha256",
        "source_commit",
        "source_tree_object_format",
        "source_tree",
        "source_tree_sha256",
        "baseline_id",
        "baseline_version",
        "baseline_sha256",
        "builder_image_digest",
        "source_date_epoch",
        "tool_versions",
        "files",
        "integrity_exclusions",
        "generated_at_utc",
        "signing_policy",
    ]
    report.require(artifact_schema.get("type") == "object" and artifact_schema.get("additionalProperties") is False, code, "artifact manifest root must be closed")
    report.require(artifact_schema.get("required") == artifact_required, code, "artifact manifest root required fields/order drift")
    artifact_properties = artifact_schema.get("properties", {})
    report.require(artifact_properties.get("schema_version", {}).get("const") == "artifact-manifest.v1", code, "artifact manifest schema version drift")
    report.require(artifact_properties.get("scope", {}).get("enum") == ["RELEASE", "DISTRIBUTION"], code, "artifact scope vocabulary drift")
    report.require(
        artifact_properties.get("source_release_manifest_sha256", {}).get("oneOf")
        == [{"type": "null"}, {"$ref": "#/$defs/sha256"}],
        code,
        "artifact distribution provenance digest type drift",
    )
    report.require(
        artifact_properties.get("files") == {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/file"}, "uniqueItems": True},
        code,
        "artifact files must contain at least one schema-bound file",
    )
    file_schema = artifact_schema.get("$defs", {}).get("file", {})
    file_required = ["path", "media_type", "size_bytes", "sha256", "owner_ids", "gate_ids", "source_paths"]
    report.require(file_schema.get("type") == "object" and file_schema.get("additionalProperties") is False, code, "artifact file row must be closed")
    report.require(file_schema.get("required") == file_required, code, "artifact file required fields/order drift")
    file_properties = file_schema.get("properties", {})
    safe_path = artifact_schema.get("$defs", {}).get("safeRelativePath", {})
    report.require(file_properties.get("path") == {"$ref": "#/$defs/safeRelativePath"} and safe_path.get("type") == "string" and safe_path.get("minLength") == 1 and is_nonempty_string(safe_path.get("pattern")), code, "artifact file path containment contract drift")
    report.require(file_properties.get("size_bytes") == {"type": "integer", "minimum": 1}, code, "artifact size constraint drift")
    report.require(file_properties.get("sha256") == {"$ref": "#/$defs/sha256"}, code, "artifact digest reference drift")
    for field in ("owner_ids", "gate_ids", "source_paths"):
        node = file_properties.get(field, {})
        report.require(node.get("type") == "array" and node.get("minItems") == 1 and node.get("uniqueItems") is True, code, f"artifact {field} cardinality/uniqueness drift")
    report.require(file_properties.get("source_paths", {}).get("items") == {"$ref": "#/$defs/safeRelativePath"}, code, "artifact source paths must use the same safe relative-path contract")
    exclusions = artifact_properties.get("integrity_exclusions", {})
    report.require(exclusions.get("minItems") == exclusions.get("maxItems") == 4 and exclusions.get("uniqueItems") is True, code, "artifact integrity exclusion set must contain exactly four unique files")
    report.require(artifact_properties.get("signing_policy", {}).get("properties", {}).get("algorithm", {}).get("const") == "Ed25519", code, "artifact signing algorithm drift")
    artifact_semantic = artifact_schema.get("x-semantic-contract", {})
    report.require(
        artifact_semantic.get("file_path_uniqueness") == "files[].path MUST be unique even when other row fields differ"
        and artifact_semantic.get("scope_containment") == "RELEASE files are relative to docs/releases/ai-training-platform/{release}; DISTRIBUTION files are relative to dist/docs/{release}; neither manifest may cross its scope root"
        and artifact_semantic.get("distribution_provenance") == "DISTRIBUTION source_release_manifest_sha256 MUST equal the verified RELEASE artifact-manifest.json SHA-256 for the same release"
        and artifact_semantic.get("content_nonempty") == "size_bytes MUST be >= 1"
        and is_nonempty_string(artifact_semantic.get("root_containment"))
        and artifact_semantic.get("fixture_release_root") == "fixtures/artifact-root/release"
        and artifact_semantic.get("fixture_source_root") == "fixtures/artifact-root/source"
        and artifact_semantic.get("actual_bytes") == "For every fixture files[] row, size_bytes and sha256 MUST equal the bytes at fixture_release_root/path"
        and artifact_semantic.get("source_resolution") == "Every fixture source_paths[] item MUST resolve to a nonempty regular file below fixture_source_root"
        and artifact_semantic.get("owner_gate_resolution") == "Every owner_ids/gate_ids member MUST resolve to the canonical requirement registry/release gate catalog"
        and artifact_semantic.get("reproducible_timestamp") == "generated_at_utc MUST equal the RFC3339 UTC instant represented by source_date_epoch"
        and artifact_semantic.get("fixtures")
        == {
            "invalid_duplicate_path": "fixtures/artifact-manifest.invalid-duplicate-path.json",
            "invalid_source_path": "fixtures/artifact-manifest.invalid-source-path.json",
        },
        code,
        "artifact manifest semantic contract drift",
    )

    evidence_required = ["schema_version", "release", "source_commit", "generated_at_utc", "overall_status", "evidence"]
    report.require(evidence_schema.get("type") == "object" and evidence_schema.get("additionalProperties") is False, code, "evidence index root must be closed")
    report.require(evidence_schema.get("required") == evidence_required, code, "evidence index root required fields/order drift")
    evidence_properties = evidence_schema.get("properties", {})
    report.require(evidence_properties.get("schema_version", {}).get("const") == "evidence-index.v1", code, "evidence index schema version drift")
    report.require(evidence_properties.get("overall_status", {}).get("enum") == ["PASS", "FAIL", "BLOCKED", "MISSING", "REQUIRES_ACCEPTANCE_DATA"], code, "evidence overall status vocabulary drift")
    report.require(
        evidence_properties.get("evidence") == {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/evidence"}},
        code,
        "evidence index must contain at least one schema-bound record",
    )
    evidence_row = evidence_schema.get("$defs", {}).get("evidence", {})
    expected_evidence_required = [
        "evidence_id",
        "requirement_ids",
        "test_ids",
        "gate_ids",
        "status",
        "freshness",
        "artifact_path",
        "artifact_sha256",
        "source_commit",
        "executed_at_utc",
        "expires_at_utc",
        "owner_ids",
        "candidate_bound",
        "dependency_fingerprint",
    ]
    report.require(evidence_row.get("type") == "object" and evidence_row.get("additionalProperties") is False, code, "evidence record must be closed")
    report.require(evidence_row.get("required") == expected_evidence_required, code, "evidence record required fields/order drift")
    row_properties = evidence_row.get("properties", {})
    report.require(row_properties.get("status", {}).get("enum") == ["PASS", "FAIL", "BLOCKED", "MISSING", "REQUIRES_ACCEPTANCE_DATA"], code, "evidence status vocabulary drift")
    report.require(row_properties.get("freshness", {}).get("enum") == ["FRESH", "STALE", "MISSING"], code, "evidence freshness vocabulary drift")
    report.require(is_nonempty_string(row_properties.get("artifact_path", {}).get("pattern")), code, "evidence artifact safe-path pattern missing")
    report.require(row_properties.get("artifact_sha256") == {"$ref": "#/$defs/sha256"}, code, "evidence artifact digest reference drift")
    report.require(row_properties.get("dependency_fingerprint") == {"$ref": "#/$defs/sha256"}, code, "evidence dependency fingerprint drift")
    report.require(row_properties.get("candidate_bound") == {"type": "boolean"}, code, "evidence candidate binding drift")
    for field in ("requirement_ids", "test_ids", "gate_ids", "owner_ids"):
        node = row_properties.get(field, {})
        report.require(node.get("type") == "array" and node.get("minItems") == 1 and node.get("uniqueItems") is True, code, f"evidence {field} cardinality/uniqueness drift")
    for field in ("executed_at_utc", "expires_at_utc"):
        report.require(row_properties.get(field, {}).get("format") == "date-time", code, f"evidence {field} date-time contract drift")
    report.pass_group(code, "artifact/evidence roots, required fields, hashes, status, paths, cardinality, and signatures are pinned", before)


def artifact_manifest_semantic_errors(
    manifest: dict[str, Any],
    *,
    release_root: Path | None = None,
    source_root: Path | None = None,
    allowed_owner_ids: set[str] | None = None,
    allowed_gate_ids: set[str] | None = None,
) -> set[str]:
    errors: set[str] = set()
    rows = manifest.get("files", [])
    if not isinstance(rows, list) or not rows:
        return {"NONEMPTY"}
    paths: list[str] = []
    reserved = {"CON", "PRN", "AUX", "NUL", *(f"COM{index}" for index in range(1, 10)), *(f"LPT{index}" for index in range(1, 10))}

    def safe_path(value: Any) -> bool:
        if not isinstance(value, str) or not value or value.startswith("/") or "\\" in value or ":" in value or "%" in value:
            return False
        if unicodedata.normalize("NFC", value) != value or any(ord(character) < 32 or ord(character) == 127 for character in value):
            return False
        parts = value.split("/")
        if any(not part or part in {".", ".."} or part.endswith((".", " ")) for part in parts):
            return False
        return all(part.split(".", 1)[0].upper() not in reserved for part in parts)

    for row in rows:
        if not isinstance(row, dict):
            errors.add("PATH")
            continue
        path = row.get("path")
        paths.append(path)
        if not safe_path(path) or not all(safe_path(source) for source in row.get("source_paths", [])):
            errors.add("PATH")
        if not isinstance(row.get("size_bytes"), int) or isinstance(row.get("size_bytes"), bool) or row.get("size_bytes", 0) < 1:
            errors.add("NONEMPTY")
        if allowed_owner_ids is not None and (
            not is_nonempty_unique_strings(row.get("owner_ids"))
            or not set(row.get("owner_ids", [])) <= allowed_owner_ids
        ):
            errors.add("OWNER")
        if allowed_gate_ids is not None and (
            not is_nonempty_unique_strings(row.get("gate_ids"))
            or not set(row.get("gate_ids", [])) <= allowed_gate_ids
        ):
            errors.add("GATE")
        if release_root is not None and safe_path(path):
            artifact_path = (release_root / path).resolve()
            try:
                contained = artifact_path.is_relative_to(release_root.resolve())
            except AttributeError:
                contained = str(artifact_path).startswith(str(release_root.resolve()) + str(Path("/")))
            if not contained or not artifact_path.is_file():
                errors.add("BYTES")
            else:
                payload = artifact_path.read_bytes()
                if len(payload) != row.get("size_bytes") or hashlib.sha256(payload).hexdigest() != row.get("sha256"):
                    errors.add("BYTES")
        if source_root is not None:
            for source_path in row.get("source_paths", []):
                if not safe_path(source_path):
                    errors.add("SOURCE")
                    continue
                resolved_source = (source_root / source_path).resolve()
                try:
                    contained = resolved_source.is_relative_to(source_root.resolve())
                except AttributeError:
                    contained = str(resolved_source).startswith(str(source_root.resolve()) + str(Path("/")))
                if not contained or not resolved_source.is_file() or resolved_source.stat().st_size < 1:
                    errors.add("SOURCE")
    if len(paths) != len(set(paths)):
        errors.add("DUPLICATE")
    scope = manifest.get("scope")
    source_release_digest = manifest.get("source_release_manifest_sha256")
    if (scope == "RELEASE" and source_release_digest is not None) or (
        scope == "DISTRIBUTION" and not bool(re.fullmatch(r"[0-9a-f]{64}", str(source_release_digest)))
    ):
        errors.add("SCOPE")
    try:
        source_date_epoch = manifest.get("source_date_epoch")
        if not isinstance(source_date_epoch, int) or isinstance(source_date_epoch, bool):
            raise TypeError("source_date_epoch must be an integer")
        generated = datetime.fromisoformat(str(manifest.get("generated_at_utc", "")).replace("Z", "+00:00"))
        if int(generated.timestamp()) != source_date_epoch or generated.utcoffset() is None or generated.utcoffset().total_seconds() != 0:
            errors.add("TIMESTAMP")
    except (TypeError, ValueError, OverflowError, AttributeError):
        errors.add("TIMESTAMP")
    return errors


def verify_artifact_semantic_fixtures(
    package_root: Path,
    schema: dict[str, Any],
    registry: dict[str, Any],
    baseline: dict[str, Any],
    report: Report,
) -> None:
    before = len(report.failures)
    code = "ARTIFACT_SEMANTICS"
    valid = load_json(package_root / "fixtures/artifact-manifest.valid.json", report)
    if isinstance(valid, dict):
        report.require(not validate_instance(schema, valid, schema), code, "valid artifact manifest failed JSON Schema")
        allowed_owner_ids = {
            owner_id
            for group in ("rfp_requirements", "system_requirements", "tests", "procedure_catalog")
            for row in registry.get(group, [])
            if isinstance(row, dict)
            for owner_id in row.get("owner_ids", [])
        }
        allowed_gate_ids = {
            row.get("id")
            for row in baseline.get("release_gates", [])
            if isinstance(row, dict) and is_nonempty_string(row.get("id"))
        }
        semantic_errors = artifact_manifest_semantic_errors(
            valid,
            release_root=package_root / "fixtures/artifact-root/release",
            source_root=package_root / "fixtures/artifact-root/source",
            allowed_owner_ids=allowed_owner_ids,
            allowed_gate_ids=allowed_gate_ids,
        )
        report.require(not semantic_errors, code, f"valid artifact manifest failed actual-byte/catalog/cross-field semantics: {sorted(semantic_errors)}")
    fixtures = schema.get("x-semantic-contract", {}).get("fixtures", {})
    expected = {
        "invalid_duplicate_path": "DUPLICATE",
        "invalid_source_path": "PATH",
    }
    for name, expected_error in expected.items():
        fixture = load_json(package_root / str(fixtures.get(name, "")), report)
        if isinstance(fixture, dict):
            report.require(expected_error in artifact_manifest_semantic_errors(fixture), code, f"{name} did not fail with {expected_error}")
    report.pass_group(code, "artifact actual bytes, canonical owners/gates/sources, scope, timestamp, paths and uniqueness are enforced", before)


def verify_static_design_contracts(package_root: Path, report: Report) -> None:
    before = len(report.failures)
    code = "STATIC_DESIGN"
    documents = {
        name: (package_root / name).read_text(encoding="utf-8")
        for name in (
            "04-ai-diagnosis-persona-recommendation.md",
            "05-document-ai-hwp-rag.md",
            "06-ai-gateway-model-selection.md",
            "07-data-api-interface-design.md",
            "10-delivery-implementation-plan.md",
            "11-codex-one-shot-implementation-prompt.md",
        )
    }
    for token in (
        "DiagnosisDecisionPolicyVersion=diagnosis-decision.v1",
        "24,999,999",
        "25,000,000",
        "49,999,999",
        "50,000,000",
        "74,999,999",
        "75,000,000",
        "confidence가 정확히 `600_000`",
        "`500_000` 이상이면 `HUMAN_REVIEW_REQUIRED`",
    ):
        report.require(token in documents["04-ai-diagnosis-persona-recommendation.md"], code, f"diagnosis decision text missing: {token}")
    hwp = documents["05-document-ai-hwp-rag.md"] + documents["11-codex-one-shot-implementation-prompt.md"]
    for token in ("child sandbox", "bridge host", "short-lived", "`BLOCKED`"):
        report.require(token in hwp, code, f"HWP trust-boundary/acceptance text missing: {token}")
    report.require("안전하게 BLOCKED가 아닌" not in hwp, code, "production HWP converter absence is still hidden as optional")
    gateway = documents["06-ai-gateway-model-selection.md"]
    report.require("[ai-gateway-request.schema.json](ai-gateway-request.schema.json)" in gateway, code, "AI Gateway design does not point to canonical schema")
    report.require('"policy_version":' not in gateway and '"provider_model":' not in gateway, code, "AI Gateway example contains a forbidden singular/provider body field")
    report.require("[entity-catalog.json](entity-catalog.json)" in documents["07-data-api-interface-design.md"] and "정확한 58개" in documents["07-data-api-interface-design.md"], code, "data design does not bind the 58-entity catalog")
    prompt = documents["11-codex-one-shot-implementation-prompt.md"]
    report.require("generated_clients/ai_gateway" in prompt and "domains, ai_gateway" not in prompt, code, "implementation prompt still places AI Gateway provider logic inside backend")
    plan = documents["10-delivery-implementation-plan.md"]
    report.require("release root와 distribution root" in plan and "source release manifest digest" in plan, code, "two-root integrity scope is absent from implementation plan")
    report.pass_group(code, "diagnosis, HWP bridge/child, AI Gateway client, entity catalog, and two-root integrity text are explicit", before)


SCHEMA_KEYWORDS = {
    "$schema", "$id", "$ref", "$defs", "title", "description", "type", "additionalProperties",
    "required", "properties", "const", "enum", "pattern", "minLength", "maxLength", "minimum", "maximum",
    "minProperties", "items", "minItems", "maxItems", "uniqueItems", "allOf", "oneOf", "not", "if", "then", "else", "contains",
    "minContains", "maxContains", "format", "x-fixture-contract",
}


def check_schema_keywords(schema: Any, path: str, errors: list[tuple[str, str]]) -> None:
    if not isinstance(schema, dict):
        errors.append(("schema", f"{path} schema node is not an object"))
        return
    for key in schema:
        if key not in SCHEMA_KEYWORDS and not key.startswith("x-"):
            errors.append(("schema", f"{path} unsupported schema keyword: {key}"))
    for container_key in ("properties", "$defs"):
        container = schema.get(container_key, {})
        if isinstance(container, dict):
            for name, child in container.items():
                check_schema_keywords(child, f"{path}/{container_key}/{name}", errors)
    for child_key in ("items", "contains", "not", "if", "then", "else"):
        child = schema.get(child_key)
        if isinstance(child, dict):
            check_schema_keywords(child, f"{path}/{child_key}", errors)
    additional = schema.get("additionalProperties")
    if isinstance(additional, dict):
        check_schema_keywords(additional, f"{path}/additionalProperties", errors)
    for index, child in enumerate(schema.get("allOf", []) if isinstance(schema.get("allOf", []), list) else []):
        check_schema_keywords(child, f"{path}/allOf/{index}", errors)
    for index, child in enumerate(schema.get("oneOf", []) if isinstance(schema.get("oneOf", []), list) else []):
        check_schema_keywords(child, f"{path}/oneOf/{index}", errors)


def json_type_matches(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    return False


def resolve_ref(root: dict[str, Any], reference: str) -> dict[str, Any] | None:
    if not reference.startswith("#/"):
        return None
    current: Any = root
    for raw_part in reference[2:].split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current if isinstance(current, dict) else None


def validate_instance(schema: dict[str, Any], instance: Any, root: dict[str, Any], path: str = "$") -> list[tuple[str, str]]:
    errors: list[tuple[str, str]] = []
    if "$ref" in schema:
        target = resolve_ref(root, schema["$ref"])
        if target is None:
            return [("$ref", f"{path} unresolved reference {schema['$ref']}")]
        return validate_instance(target, instance, root, path)
    for child in schema.get("allOf", []):
        errors.extend(validate_instance(child, instance, root, path))
    if isinstance(schema.get("oneOf"), list):
        branch_errors = [validate_instance(child, instance, root, path) for child in schema["oneOf"]]
        matches = sum(not item for item in branch_errors)
        if matches != 1:
            errors.append(("oneOf", f"{path} matches {matches} oneOf branches"))
    if isinstance(schema.get("not"), dict) and not validate_instance(schema["not"], instance, root, path):
        errors.append(("not", f"{path} matches a forbidden schema"))
    if isinstance(schema.get("if"), dict):
        condition_matches = not validate_instance(schema["if"], instance, root, path)
        branch = schema.get("then") if condition_matches else schema.get("else")
        if isinstance(branch, dict):
            errors.extend(validate_instance(branch, instance, root, path))

    expected_type = schema.get("type")
    if expected_type is not None:
        types = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(isinstance(item, str) and json_type_matches(instance, item) for item in types):
            return [("type", f"{path} expected {types}, got {type(instance).__name__}")]
    if "const" in schema and instance != schema["const"]:
        errors.append(("const", f"{path} does not equal const"))
    if "enum" in schema and instance not in schema["enum"]:
        errors.append(("enum", f"{path} is not an allowed enum value"))

    if isinstance(instance, dict):
        required = schema.get("required", [])
        for name in required:
            if name not in instance:
                errors.append(("required", f"{path} missing required property {name}"))
        properties = schema.get("properties", {})
        for name, value in instance.items():
            if name in properties:
                errors.extend(validate_instance(properties[name], value, root, f"{path}/{name}"))
            elif schema.get("additionalProperties") is False:
                errors.append(("additionalProperties", f"{path} unexpected property {name}"))
            elif isinstance(schema.get("additionalProperties"), dict):
                errors.extend(validate_instance(schema["additionalProperties"], value, root, f"{path}/{name}"))
        if isinstance(schema.get("minProperties"), int) and len(instance) < schema["minProperties"]:
            errors.append(("minProperties", f"{path} has too few properties"))

    if isinstance(instance, list):
        if isinstance(schema.get("minItems"), int) and len(instance) < schema["minItems"]:
            errors.append(("minItems", f"{path} has too few items"))
        if isinstance(schema.get("maxItems"), int) and len(instance) > schema["maxItems"]:
            errors.append(("maxItems", f"{path} has too many items"))
        if schema.get("uniqueItems") is True:
            serialized = [canonical_json(item) for item in instance]
            if len(serialized) != len(set(serialized)):
                errors.append(("uniqueItems", f"{path} contains duplicate items"))
        if isinstance(schema.get("items"), dict):
            for index, value in enumerate(instance):
                errors.extend(validate_instance(schema["items"], value, root, f"{path}/{index}"))
        if isinstance(schema.get("contains"), dict):
            matches = sum(not validate_instance(schema["contains"], value, root, f"{path}/{index}") for index, value in enumerate(instance))
            minimum = schema.get("minContains", 1)
            maximum = schema.get("maxContains")
            if matches < minimum:
                errors.append(("minContains", f"{path} contains only {matches} matching items"))
            if isinstance(maximum, int) and matches > maximum:
                errors.append(("maxContains", f"{path} contains {matches} matching items"))

    if isinstance(instance, str):
        if isinstance(schema.get("minLength"), int) and len(instance) < schema["minLength"]:
            errors.append(("minLength", f"{path} is too short"))
        if isinstance(schema.get("maxLength"), int) and len(instance) > schema["maxLength"]:
            errors.append(("maxLength", f"{path} is too long"))
        if isinstance(schema.get("pattern"), str) and re.search(schema["pattern"], instance) is None:
            errors.append(("pattern", f"{path} does not match pattern"))
        if schema.get("format") == "date-time":
            try:
                parsed = datetime.fromisoformat(instance.replace("Z", "+00:00"))
                if parsed.tzinfo is None:
                    raise ValueError("timezone required")
            except ValueError:
                errors.append(("format", f"{path} is not an RFC 3339 date-time"))

    if isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if isinstance(schema.get("minimum"), (int, float)) and instance < schema["minimum"]:
            errors.append(("minimum", f"{path} is below minimum"))
        if isinstance(schema.get("maximum"), (int, float)) and instance > schema["maximum"]:
            errors.append(("maximum", f"{path} is above maximum"))
    return errors


def verify_schema_fixtures(package_root: Path, schemas: list[tuple[str, dict[str, Any]]], report: Report) -> None:
    before = len(report.failures)
    code = "SCHEMA_FIXTURES"
    for schema_name, schema in schemas:
        report.require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", code, f"{schema_name} must declare Draft 2020-12")
        keyword_errors: list[tuple[str, str]] = []
        check_schema_keywords(schema, "$", keyword_errors)
        for _, message in keyword_errors:
            report.require(False, code, f"{schema_name}: {message}")
        fixture_contract = schema.get("x-fixture-contract", {})
        positive_path = fixture_contract.get("positive")
        negative_path = fixture_contract.get("negative")
        expected_keyword = fixture_contract.get("negative_must_fail_keyword")
        report.require(all(is_nonempty_string(value) for value in (positive_path, negative_path, expected_keyword)), code, f"{schema_name} fixture contract incomplete")
        if not all(is_nonempty_string(value) for value in (positive_path, negative_path, expected_keyword)):
            continue
        positive = load_json(package_root / positive_path, report)
        negative = load_json(package_root / negative_path, report)
        if positive is None or negative is None:
            continue
        positive_errors = validate_instance(schema, positive, schema)
        negative_errors = validate_instance(schema, negative, schema)
        report.require(not positive_errors, code, f"{schema_name} positive fixture failed: {positive_errors[:3]}")
        report.require(bool(negative_errors), code, f"{schema_name} negative fixture unexpectedly passed")
        report.require(expected_keyword in {keyword for keyword, _ in negative_errors}, code, f"{schema_name} negative fixture did not fail at {expected_keyword}")
    report.pass_group(code, "artifact/evidence valid fixtures pass and declared invalid fixtures fail", before)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify YOnLab machine-readable design contracts")
    parser.add_argument("--package-root", type=Path, default=Path(__file__).resolve().parent, help="path containing design contract JSON files")
    return parser.parse_args(argv)


def run(argv: list[str]) -> int:
    args = parse_args(argv)
    package_root = args.package_root.resolve()
    report = Report()
    if not package_root.is_dir():
        report.require(False, "INPUT", f"package root is not a directory: {package_root}")
        return report.finish()

    names = [
        "design-baseline.json",
        "requirements-test-registry.json",
        "screen-route-contracts.json",
        "entity-catalog.json",
        "kpi-005-structured-output-matrix.json",
        "diagnosis-scoring-golden-vectors.json",
        "ai-gateway-request.schema.json",
        "hwp-conversion-boundary-contract.json",
        "source-tree-hash-golden-vector.json",
        "final-document-inventory.json",
        "document-graph.schema.json",
        "artifact-manifest.schema.json",
        "evidence-index.schema.json",
    ]
    loaded = {name: load_json(package_root / name, report) for name in names}
    if any(loaded[name] is None for name in names):
        return report.finish()
    if not all(isinstance(loaded[name], dict) for name in names):
        report.require(False, "JSON_PARSE", "every machine contract root must be a JSON object")
        return report.finish()

    try:
        verify_pinned_semantic_contracts(package_root, report)
        verify_registry(loaded["requirements-test-registry.json"], loaded["screen-route-contracts.json"], loaded["design-baseline.json"], package_root, report)
        verify_screens(loaded["screen-route-contracts.json"], loaded["requirements-test-registry.json"], report)
        verify_api_operation_resolution(loaded["requirements-test-registry.json"], loaded["screen-route-contracts.json"], report)
        verify_entity_catalog(loaded["entity-catalog.json"], loaded["requirements-test-registry.json"], report)
        verify_kpi_matrix(loaded["kpi-005-structured-output-matrix.json"], report)
        verify_diagnosis_vectors(loaded["diagnosis-scoring-golden-vectors.json"], report)
        verify_ai_gateway_schema(loaded["ai-gateway-request.schema.json"], package_root, report)
        verify_hwp_boundary(loaded["hwp-conversion-boundary-contract.json"], report)
        verify_source_tree_vector(loaded["source-tree-hash-golden-vector.json"], report)
        verify_final_document_inventory(loaded["final-document-inventory.json"], report)
        verify_document_graph_schema(loaded["document-graph.schema.json"], report)
        verify_document_graph_fixtures(package_root, loaded["document-graph.schema.json"], report)
        verify_release_schema_cores(
            loaded["artifact-manifest.schema.json"],
            loaded["evidence-index.schema.json"],
            report,
        )
        verify_artifact_semantic_fixtures(
            package_root,
            loaded["artifact-manifest.schema.json"],
            loaded["requirements-test-registry.json"],
            loaded["design-baseline.json"],
            report,
        )
        verify_static_design_contracts(package_root, report)
        verify_schema_fixtures(
            package_root,
            [
                ("artifact-manifest.schema.json", loaded["artifact-manifest.schema.json"]),
                ("evidence-index.schema.json", loaded["evidence-index.schema.json"]),
                ("ai-gateway-request.schema.json", loaded["ai-gateway-request.schema.json"]),
            ],
            report,
        )
    except Exception as exc:  # fail closed without leaking a traceback into automation output
        report.require(False, "INTERNAL", f"unhandled verifier error: {type(exc).__name__}: {exc}")
    return report.finish()


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
