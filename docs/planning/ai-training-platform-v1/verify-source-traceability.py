#!/usr/bin/env python3
"""Fail-closed verifier for the public-safe private-source trace package."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import unicodedata
import zipfile
from pathlib import Path
from typing import Any
from xml.etree import ElementTree


EXPECTED_TOP_KEYS = {
    "schema_version",
    "trace_baseline_date",
    "public_safety",
    "hash_contract",
    "sources",
    "rfp_requirements",
    "proposal_topics",
    "accuracy_limitations",
}
EXPECTED_SOURCE_FILES = {
    "SRC-RFP-2026-05": {
        "file_name": "(제안요청서)보육교사 맞춤형 연수혁신 AI 서비스 고도화-조달의견반영.pdf",
        "bytes": 2_141_467,
        "sha256": "2d9e23088b3e2234af8cca49847c1226840695660780b39ad549381e51a5f959",
        "pages": 74,
    },
    "SRC-PROPOSAL-V04": {
        "file_name": "와이온랩_보육교사 맞춤형 연수혁신 AI 서비스 고도화 제안서_v0.4_개발설계보강.docx",
        "bytes": 17_475_962,
        "sha256": "53af230c1fbbd9f4efc504c749ed17810922080ff1b3d9d4efab423d9043da27",
        "docprops_pages": 179,
        "reference_rendered_pages": 135,
        "body_children": 1_755,
        "paragraphs": 1_489,
        "tables": 264,
    },
}
EXPECTED_DIGESTS = {
    "public_safety": "0737adc6c1f2c39e6b7ea779fdaca5114fc648cda0176231bab00faffe69ad53",
    "hash_contract": "373358cd39ccb525e21d62af3bd1de1ae8c650ef338ef8b899bd0d3107ef64c5",
    "sources": "9c660231c89880cb8a4043c7b4ad4c100f815f702ebd188e1454682fc76f316f",
    "rfp_requirements": "8439c1f212dcbfb4c28222bd07c8b31135f44932ab64a14c8857849bf2ab1d95",
    "proposal_topics": "3cd5c9747080a3734f82181b1e84f0b697e899a09a8863a1b48b5e2a245451fb",
    "accuracy_limitations": "1a280394acb05c065c9382bf9788cc0cfe7356b5c03ca54d3dac4b8499b5ffb5",
}
EXPECTED_RFP_PREFIX_COUNTS = {
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
EXPECTED_OBLIGATION_TYPES = {
    "PLR": "PLANNING",
    "ECR": "ENVIRONMENT_PROVISIONING",
    "DER": "FUNCTIONAL_DELIVERY",
    "SIR": "INTERFACE_DELIVERY",
    "DAR": "DATA_GOVERNANCE",
    "TER": "VERIFICATION",
    "SER": "SECURITY_CONTROL",
    "QUR": "QUALITY_CONTROL",
    "COR": "CONTRACTUAL_CONSTRAINT",
    "PMR": "PROJECT_MANAGEMENT",
    "PSR": "SERVICE_SUPPORT",
}
EXPECTED_TOPIC_IDS = {
    "PROPOSAL-DIAGNOSIS",
    "PROPOSAL-PERSONA",
    "PROPOSAL-RECOMMENDATION",
    "PROPOSAL-HWP-RAG",
    "PROPOSAL-AI-GATEWAY",
    "PROPOSAL-UI",
    "PROPOSAL-PILOT",
    "PROPOSAL-OPERATIONS",
}
RFP_ROW_KEYS = {
    "requirement_id",
    "source_id",
    "physical_pages",
    "printed_page_labels",
    "section_path",
    "section_title",
    "paraphrase",
    "obligation_level",
    "obligation_type",
    "acceptance_test_ids",
    "design_ids",
}
TOPIC_KEYS = {
    "topic_id",
    "source_id",
    "summary",
    "requirement_ids",
    "design_ids",
    "locators",
}
FORBIDDEN_PUBLIC_KEYS = {
    "source_excerpt",
    "verbatim_excerpt",
    "raw_text",
    "source_text",
    "absolute_path",
    "private_path",
    "private_source_path",
}
WINDOWS_ABSOLUTE = re.compile(r"^[A-Za-z]:[\\/]")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
W_NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
APP_NS = "{http://schemas.openxmlformats.org/officeDocument/2006/extended-properties}"


class TraceError(RuntimeError):
    """A source trace contract violation."""


def fail(message: str) -> None:
    raise TraceError(message)


def strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    seen: set[str] = set()
    for key, value in pairs:
        folded = key.casefold()
        if folded in seen:
            fail(f"duplicate JSON property (case-insensitive): {key}")
        seen.add(folded)
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=strict_object)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"cannot read strict JSON {path.name}: {exc}")


def exact_keys(value: Any, expected: set[str], label: str) -> None:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    actual = set(value)
    if actual != expected:
        fail(f"{label} property set mismatch: missing={sorted(expected-actual)}, extra={sorted(actual-expected)}")


def canonical_digest(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def require_nonempty_strings(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or not value:
        fail(f"{label} must be a nonempty array")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        fail(f"{label} must contain nonempty strings")
    if len(value) != len(set(value)):
        fail(f"{label} contains duplicates")
    return value


def walk_public(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in FORBIDDEN_PUBLIC_KEYS:
                fail(f"forbidden private/verbatim field at {path}.{key}")
            walk_public(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            walk_public(child, f"{path}[{index}]")
    elif isinstance(value, str):
        if WINDOWS_ABSOLUTE.match(value) or value.startswith(("/workspace/", "/home/", "upload/")):
            fail(f"private/absolute source path leaked at {path}")


def verify_public_safety(root: Path, manifest: dict[str, Any]) -> None:
    public = manifest["public_safety"]
    exact_keys(
        public,
        {"public_safe", "contains_source_originals", "contains_verbatim_excerpts", "locator_only_policy"},
        "public_safety",
    )
    if public["public_safe"] is not True or public["contains_source_originals"] is not False or public["contains_verbatim_excerpts"] is not False:
        fail("public safety booleans must declare a locator-only package")
    walk_public(manifest)
    for expected in EXPECTED_SOURCE_FILES.values():
        copied = list(root.rglob(expected["file_name"]))
        if copied:
            fail(f"private source original copied into design package: {expected['file_name']}")
    print("PASS [PUBLIC_SAFE]: no private originals, absolute paths, or verbatim source fields")


def verify_sources(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    sources = manifest["sources"]
    if not isinstance(sources, list) or len(sources) != 2:
        fail("sources must contain exactly RFP and proposal metadata")
    indexed: dict[str, dict[str, Any]] = {}
    for source in sources:
        if not isinstance(source, dict) or not isinstance(source.get("source_id"), str):
            fail("invalid source metadata row")
        source_id = source["source_id"]
        if source_id in indexed:
            fail(f"duplicate source_id: {source_id}")
        indexed[source_id] = source
    if set(indexed) != set(EXPECTED_SOURCE_FILES):
        fail("source IDs differ from the pinned RFP/proposal pair")

    rfp = indexed["SRC-RFP-2026-05"]
    exact_keys(
        rfp,
        {"source_id", "source_role", "file_name", "media_type", "bytes", "sha256", "page_count", "detail_locator_contract"},
        "RFP source",
    )
    proposal = indexed["SRC-PROPOSAL-V04"]
    exact_keys(
        proposal,
        {"source_id", "source_role", "file_name", "media_type", "bytes", "sha256", "page_count", "opc_inventory"},
        "proposal source",
    )
    for source_id, expected in EXPECTED_SOURCE_FILES.items():
        row = indexed[source_id]
        if row["file_name"] != expected["file_name"] or row["bytes"] != expected["bytes"] or row["sha256"] != expected["sha256"]:
            fail(f"{source_id} exact byte identity drift")
        if not SHA256.fullmatch(row["sha256"]):
            fail(f"{source_id} SHA-256 is malformed")
    if rfp["source_role"] != "CONTRACTUAL_RFP" or rfp["media_type"] != "application/pdf":
        fail("RFP role/media type drift")
    if rfp["page_count"] != {"physical_pdf_pages": 74, "authority": "PDF physical pages are one-based and authoritative for RFP locators."}:
        fail("RFP physical page contract drift")
    if rfp["detail_locator_contract"] != {"list_pages": [9, 10], "detail_physical_page_range": [11, 38], "requirement_count": 60}:
        fail("RFP detail locator contract drift")
    if proposal["source_role"] != "TECHNICAL_PROPOSAL" or proposal["media_type"] != "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
        fail("proposal role/media type drift")
    page_count = proposal["page_count"]
    if page_count.get("docprops_declared_pages") != 179 or page_count.get("reference_rendered_pages") != 135:
        fail("proposal declared/reference page count drift")
    if proposal["opc_inventory"] != {"part": "word/document.xml", "body_child_count": 1755, "paragraph_count": 1489, "table_count": 264}:
        fail("proposal OPC inventory drift")
    print("PASS [SOURCE_METADATA]: exact SHA-256, byte counts, page counts, and OPC inventory are pinned")
    return indexed


def verify_rfp(manifest: dict[str, Any], registry: dict[str, Any]) -> None:
    rows = manifest["rfp_requirements"]
    registry_rows = registry.get("rfp_requirements")
    tests = registry.get("tests")
    if not isinstance(rows, list) or len(rows) != 60 or not isinstance(registry_rows, list) or len(registry_rows) != 60:
        fail("manifest and registry must each contain exactly 60 RFP requirements")
    if not isinstance(tests, list):
        fail("registry tests must be an array")
    known_tests = {item.get("test_id") for item in tests if isinstance(item, dict)}
    registry_by_id = {item.get("requirement_id"): item for item in registry_rows if isinstance(item, dict)}
    ids: list[str] = []
    prefix_counts = {prefix: 0 for prefix in EXPECTED_RFP_PREFIX_COUNTS}
    for row in rows:
        exact_keys(row, RFP_ROW_KEYS, "RFP trace row")
        requirement_id = row["requirement_id"]
        if not isinstance(requirement_id, str) or not re.fullmatch(r"[A-Z]{3}-\d{3}", requirement_id):
            fail("malformed RFP requirement ID")
        ids.append(requirement_id)
        prefix = requirement_id[:3]
        if prefix not in prefix_counts:
            fail(f"unknown RFP prefix: {prefix}")
        prefix_counts[prefix] += 1
        if row["source_id"] != "SRC-RFP-2026-05":
            fail(f"{requirement_id} must trace to the exact RFP source")
        pages = row["physical_pages"]
        if not isinstance(pages, list) or not pages or any(type(page) is not int or page < 11 or page > 38 for page in pages):
            fail(f"{requirement_id} must use detailed physical pages 11..38, not list pages 9/10")
        if pages != sorted(set(pages)) or any(right != left + 1 for left, right in zip(pages, pages[1:])):
            fail(f"{requirement_id} physical pages must be unique contiguous pages")
        expected_printed = [str(page - 2) for page in pages]
        if row["printed_page_labels"] != expected_printed:
            fail(f"{requirement_id} printed page labels do not match physical-page offset")
        section_path = require_nonempty_strings(row["section_path"], f"{requirement_id}.section_path")
        if section_path[:2] != ["Ⅲ. 제안 요청 내용", "3. 세부요구 사항"]:
            fail(f"{requirement_id} detailed section root drift")
        if not isinstance(row["section_title"], str) or not row["section_title"].strip():
            fail(f"{requirement_id} detailed section title is empty")
        if not isinstance(row["paraphrase"], str) or not row["paraphrase"].strip():
            fail(f"{requirement_id} public paraphrase is empty")
        if row["obligation_level"] != "MANDATORY" or row["obligation_type"] != EXPECTED_OBLIGATION_TYPES[prefix]:
            fail(f"{requirement_id} obligation classification drift")
        reg = registry_by_id.get(requirement_id)
        if reg is None:
            fail(f"{requirement_id} missing from normative registry")
        tests_for_row = require_nonempty_strings(row["acceptance_test_ids"], f"{requirement_id}.acceptance_test_ids")
        designs_for_row = require_nonempty_strings(row["design_ids"], f"{requirement_id}.design_ids")
        if tests_for_row != reg.get("test_ids") or designs_for_row != reg.get("design_ids"):
            fail(f"{requirement_id} acceptance/design edges differ from normative registry")
        if row["paraphrase"] != reg.get("title"):
            fail(f"{requirement_id} paraphrase differs from registry title")
        if any(test_id not in known_tests for test_id in tests_for_row):
            fail(f"{requirement_id} references an unknown acceptance test")
    if len(ids) != len(set(ids)) or set(ids) != set(registry_by_id):
        fail("RFP requirement IDs are duplicate, missing, or extra")
    if prefix_counts != EXPECTED_RFP_PREFIX_COUNTS:
        fail(f"RFP prefix cardinality drift: {prefix_counts}")
    if next(row for row in rows if row["requirement_id"] == "PLR-002")["physical_pages"] != [11, 12]:
        fail("PLR-002 must preserve its two-page detailed block")
    if any(len(row["physical_pages"]) != 1 for row in rows if row["requirement_id"] != "PLR-002"):
        fail("PLR-002 is the only multi-page detailed requirement block")
    print("PASS [RFP_TRACE]: 60/60 requirements map to detailed physical pages and exact registry test/design edges")


def verify_topics(manifest: dict[str, Any], registry: dict[str, Any]) -> None:
    topics = manifest["proposal_topics"]
    if not isinstance(topics, list) or len(topics) != 8:
        fail("proposal_topics must contain exactly eight required topics")
    ids = [topic.get("topic_id") for topic in topics if isinstance(topic, dict)]
    if len(ids) != len(set(ids)) or set(ids) != EXPECTED_TOPIC_IDS:
        fail("proposal topic IDs are duplicate, missing, or extra")
    known_requirements = {row.get("requirement_id") for row in registry.get("rfp_requirements", []) if isinstance(row, dict)}
    seen_locator_keys: set[tuple[int, str, int]] = set()
    for topic in topics:
        exact_keys(topic, TOPIC_KEYS, "proposal topic")
        topic_id = topic["topic_id"]
        if topic["source_id"] != "SRC-PROPOSAL-V04" or not isinstance(topic["summary"], str) or not topic["summary"].strip():
            fail(f"{topic_id} source/summary contract drift")
        requirement_ids = require_nonempty_strings(topic["requirement_ids"], f"{topic_id}.requirement_ids")
        require_nonempty_strings(topic["design_ids"], f"{topic_id}.design_ids")
        if any(requirement_id not in known_requirements for requirement_id in requirement_ids):
            fail(f"{topic_id} references an unknown RFP requirement")
        locators = topic["locators"]
        if not isinstance(locators, list) or len(locators) != 2:
            fail(f"{topic_id} must contain a heading and implementation-table locator")
        purposes: set[str] = set()
        kinds: set[str] = set()
        for locator in locators:
            if not isinstance(locator, dict):
                fail(f"{topic_id} locator must be an object")
            element_type = locator.get("element_type")
            if element_type == "paragraph":
                expected_keys = {"opc_part", "body_child_index", "element_type", "paragraph_index", "normalized_text_sha256", "purpose"}
                type_index = locator.get("paragraph_index")
                upper_bound = 1489
            elif element_type == "table":
                expected_keys = {"opc_part", "body_child_index", "element_type", "table_index", "normalized_text_sha256", "purpose"}
                type_index = locator.get("table_index")
                upper_bound = 264
            else:
                fail(f"{topic_id} locator element_type is invalid")
            exact_keys(locator, expected_keys, f"{topic_id} locator")
            if locator["opc_part"] != "word/document.xml":
                fail(f"{topic_id} locator OPC part drift")
            if type(locator["body_child_index"]) is not int or not 0 <= locator["body_child_index"] < 1755:
                fail(f"{topic_id} body child index out of range")
            if type(type_index) is not int or not 0 <= type_index < upper_bound:
                fail(f"{topic_id} type-specific index out of range")
            digest = locator["normalized_text_sha256"]
            if not isinstance(digest, str) or not SHA256.fullmatch(digest):
                fail(f"{topic_id} locator text digest malformed")
            purposes.add(locator["purpose"])
            kinds.add(element_type)
            key = (locator["body_child_index"], element_type, type_index)
            if key in seen_locator_keys:
                fail(f"proposal locator reused across topics: {key}")
            seen_locator_keys.add(key)
        if kinds != {"paragraph", "table"} or "SECTION_HEADING" not in purposes:
            fail(f"{topic_id} must bind one section heading and one implementation table")
    print("PASS [PROPOSAL_TRACE]: 8/8 topics bind unique OPC heading/table locators and text fingerprints")


def verify_golden_digests(manifest: dict[str, Any]) -> None:
    for key, expected in EXPECTED_DIGESTS.items():
        actual = canonical_digest(manifest[key])
        if actual != expected:
            fail(f"{key} canonical trace digest drift: expected {expected}, got {actual}")
    print("PASS [PINNED_TRACE]: public policy, sources, 60 RFP rows, 8 proposal topics, and limitations match golden digests")


def verify_mirror(root: Path, manifest: dict[str, Any]) -> None:
    path = root / "source-traceability.md"
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        fail(f"cannot read source traceability mirror: {exc}")
    required_tokens = [
        "60/60",
        "physical 11~38",
        "OPC",
        EXPECTED_SOURCE_FILES["SRC-RFP-2026-05"]["sha256"],
        EXPECTED_SOURCE_FILES["SRC-PROPOSAL-V04"]["sha256"],
        *sorted(EXPECTED_TOPIC_IDS),
    ]
    for token in required_tokens:
        if token not in text:
            fail(f"source traceability mirror missing token: {token}")
    for source in manifest["sources"]:
        if source["file_name"] not in text:
            fail(f"source traceability mirror missing source name: {source['file_name']}")
    print("PASS [MIRROR]: concise public-safe mirror names both sources, 60/60 coverage, and all proposal topics")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalized_opc_text(element: ElementTree.Element) -> str:
    combined = "".join(element.itertext())
    return " ".join(unicodedata.normalize("NFC", combined).split())


def verify_private_sources(private_root: Path, manifest: dict[str, Any]) -> None:
    if not private_root.is_dir():
        fail(f"private source directory does not exist: {private_root}")
    by_id = {source["source_id"]: source for source in manifest["sources"]}
    paths: dict[str, Path] = {}
    for source_id, expected in EXPECTED_SOURCE_FILES.items():
        source_path = private_root / expected["file_name"]
        if not source_path.is_file():
            fail(f"private source missing: {expected['file_name']}")
        if source_path.stat().st_size != expected["bytes"] or file_sha256(source_path) != expected["sha256"]:
            fail(f"private source exact bytes differ: {source_id}")
        paths[source_id] = source_path
        if by_id[source_id]["sha256"] != expected["sha256"]:
            fail(f"manifest/private source digest mismatch: {source_id}")

    pdfinfo = shutil.which("pdfinfo")
    if pdfinfo is None:
        fail("pdfinfo is required for optional private-source PDF page verification")
    completed = subprocess.run(
        [pdfinfo, str(paths["SRC-RFP-2026-05"])],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    page_match = re.search(r"^Pages:\s+(\d+)\s*$", completed.stdout, re.MULTILINE)
    if completed.returncode != 0 or page_match is None or int(page_match.group(1)) != 74:
        fail("private RFP does not report exactly 74 physical pages")

    proposal_path = paths["SRC-PROPOSAL-V04"]
    with zipfile.ZipFile(proposal_path) as archive:
        try:
            document_root = ElementTree.fromstring(archive.read("word/document.xml"))
            app_root = ElementTree.fromstring(archive.read("docProps/app.xml"))
        except (KeyError, ElementTree.ParseError) as exc:
            fail(f"proposal OPC cannot be parsed: {exc}")
    body = document_root.find(f".//{W_NS}body")
    if body is None:
        fail("proposal OPC body is missing")
    children = list(body)
    paragraphs = [child for child in children if child.tag == f"{W_NS}p"]
    tables = [child for child in children if child.tag == f"{W_NS}tbl"]
    if (len(children), len(paragraphs), len(tables)) != (1755, 1489, 264):
        fail("private proposal OPC inventory differs from manifest")
    pages_element = app_root.find(f".//{APP_NS}Pages")
    if pages_element is None or pages_element.text != "179":
        fail("private proposal docProps declared page count differs")

    paragraph_index = {id(element): index for index, element in enumerate(paragraphs)}
    table_index = {id(element): index for index, element in enumerate(tables)}
    for topic in manifest["proposal_topics"]:
        for locator in topic["locators"]:
            body_index = locator["body_child_index"]
            element = children[body_index]
            expected_tag = f"{W_NS}{'p' if locator['element_type'] == 'paragraph' else 'tbl'}"
            if element.tag != expected_tag:
                fail(f"{topic['topic_id']} body child element type differs")
            if locator["element_type"] == "paragraph":
                actual_type_index = paragraph_index[id(element)]
                expected_type_index = locator["paragraph_index"]
            else:
                actual_type_index = table_index[id(element)]
                expected_type_index = locator["table_index"]
            if actual_type_index != expected_type_index:
                fail(f"{topic['topic_id']} type-specific OPC index differs")
            actual_digest = hashlib.sha256(normalized_opc_text(element).encode("utf-8")).hexdigest()
            if actual_digest != locator["normalized_text_sha256"]:
                fail(f"{topic['topic_id']} normalized OPC text fingerprint differs")
    print("PASS [PRIVATE_SOURCE]: exact private bytes, 74 PDF pages, DOCX properties, and 16 OPC locators verified")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--private-source-dir", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    try:
        manifest = load_json(root / "source-traceability-manifest.json")
        registry = load_json(root / "requirements-test-registry.json")
        exact_keys(manifest, EXPECTED_TOP_KEYS, "source traceability manifest")
        if manifest["schema_version"] != "source-traceability-manifest.v1" or manifest["trace_baseline_date"] != "2026-07-14":
            fail("source trace schema version/baseline date drift")
        verify_public_safety(root, manifest)
        verify_sources(manifest)
        verify_rfp(manifest, registry)
        verify_topics(manifest, registry)
        verify_golden_digests(manifest)
        verify_mirror(root, manifest)
        if args.private_source_dir is not None:
            verify_private_sources(args.private_source_dir.resolve(), manifest)
        else:
            print("INFO [PRIVATE_SOURCE]: optional exact-source revalidation not requested; pinned byte identities remain enforced")
    except TraceError as exc:
        print(f"FAIL [SOURCE_TRACE]: {exc}", file=sys.stderr)
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
