#!/usr/bin/env python3
"""Generate or verify the canonical YOnLab v1.1 overlay manifest.

The mapping policy is intentionally code-owned and closed.  Every regular
design-package file is installed recursively except the three package-only
verifiers.  Private sources, caches, links, and undeclared top-level sources
can therefore never enter the overlay by merely editing the JSON manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import tempfile
import unicodedata
from typing import Any


POLICY_PARITY_MARKER = "OVERLAY_POLICY_V2_RECURSIVE_EXACT"
MANIFEST_VERSION = "overlay.v2"
BASELINE_ID = "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1"
TARGET_ROOT = r"D:\Views\yonlab-inuri-site"
TARGET_BRANCH = "feat/ai-training-platform-v1"
TARGET_REMOTE = "https://github.com/yubi-lee/yonlab-i-nuri-site.git"
PACKAGE_DIRECTORY = "yonlab-ai-training-platform-design"
PACKAGE_DESTINATION = "docs/planning/ai-training-platform-v1"
REPO_OVERLAY_DIRECTORY = "repo-overlay"
PACKAGE_ONLY_EXCLUSIONS = (
    "test-verify-design-package.sh",
    "verify-design-package.ps1",
    "verify-design-package.sh",
)
REJECTED_NON_SOURCE_PARTS = {
    ".artifacts",
    ".git",
    ".superpowers",
    "__pycache__",
    "coverage",
    "playwright-report",
    "test-results",
    "node_modules",
}
REJECTED_NON_SOURCE_SUFFIXES = {".pyc", ".pyo"}
WINDOWS_RESERVED_BASENAMES = {
    "con", "prn", "aux", "nul",
    *(f"com{index}" for index in range(1, 10)),
    *(f"lpt{index}" for index in range(1, 10)),
}
WINDOWS_INVALID_SEGMENT_CHARACTERS = set('<>:"/\\|?*')
INSTALL_MODE = "100644"
STATIC_MAPPINGS = (
    (
        "AI-Gateway-UniClaudeProxy-Reuse-Design.md",
        "docs/planning/AI-Gateway-UniClaudeProxy-Reuse-Design.md",
    ),
    (
        "generate-overlay-manifest.py",
        f"{PACKAGE_DESTINATION}/tools/generate-overlay-manifest.py",
    ),
)


class ManifestError(RuntimeError):
    """A deterministic package or manifest contract violation."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ManifestError(message)


def reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    folded: set[str] = set()
    for key, item in pairs:
        require(key not in value and key.casefold() not in folded, f"duplicate JSON property: {key}")
        value[key] = item
        folded.add(key.casefold())
    return value


def validate_all_mapped_json(root: Path, mapping: list[tuple[str, str]]) -> None:
    """Strictly parse every JSON file that the overlay can install.

    The policy is mapping-owned rather than directory-owned so a future JSON
    registry under repo-overlay cannot bypass duplicate-key/UTF-8 validation.
    """

    json_sources = sorted(
        source for source, _ in mapping if PurePosixPath(source).suffix.casefold() == ".json"
    )
    for relative in json_sources:
        path = validate_regular_source(root, relative)
        try:
            json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_json_keys)
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise ManifestError(f"invalid strict UTF-8 JSON source {relative}: {exc}") from exc


def validate_relative(value: str, label: str) -> None:
    require(value == unicodedata.normalize("NFC", value), f"{label} is not NFC: {value!r}")
    require("\\" not in value, f"{label} must use POSIX separators: {value!r}")
    path = PurePosixPath(value)
    require(bool(value) and not path.is_absolute(), f"{label} must be relative: {value!r}")
    require(all(part not in {"", ".", ".."} for part in path.parts), f"unsafe {label}: {value!r}")
    require(not any(ord(character) < 32 or ord(character) == 127 for character in value), f"control character in {label}")
    for segment in path.parts:
        require(segment == segment.rstrip(" ."), f"Windows-unsafe trailing dot/space in {label}: {value!r}")
        require(not any(character in WINDOWS_INVALID_SEGMENT_CHARACTERS for character in segment), f"Windows-invalid character in {label}: {value!r}")
        basename = segment.split(".", 1)[0].casefold()
        require(basename not in WINDOWS_RESERVED_BASENAMES, f"Windows reserved device name in {label}: {value!r}")


def path_collision_key(value: str) -> str:
    return unicodedata.normalize("NFC", value).casefold()


def is_reparse_or_mount(path: Path) -> bool:
    metadata = path.lstat()
    attributes = getattr(metadata, "st_file_attributes", 0)
    reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0)
    return bool(reparse_flag and attributes & reparse_flag) or path.is_symlink() or path.is_mount()


def validate_source_relative_policy(relative: str) -> None:
    validate_relative(relative, "source-tree relative path")
    parts = PurePosixPath(relative).parts
    folded = tuple(part.casefold() for part in parts)
    require(not any(part in REJECTED_NON_SOURCE_PARTS for part in folded), f"generated/private directory is forbidden: {relative}")
    require(not any(
        folded[index] == "reference" and folded[index + 1] == "private"
        for index in range(len(folded) - 1)
    ), f"private reference subtree is forbidden: {relative}")
    require(PurePosixPath(relative).suffix.casefold() not in REJECTED_NON_SOURCE_SUFFIXES, f"generated cache file is forbidden: {relative}")


def validate_regular_source(root: Path, source: str) -> Path:
    validate_relative(source, "overlay source")
    candidate = root / PurePosixPath(source)
    require(candidate.exists(), f"overlay source is missing: {source}")
    require(not is_reparse_or_mount(candidate), f"overlay source may not be a link, reparse point, junction, or mount: {source}")
    require(stat.S_ISREG(candidate.lstat().st_mode), f"overlay source is not a regular file: {source}")
    require(candidate.stat().st_size > 0, f"overlay source is empty: {source}")
    return candidate


def discover_tree_mapping(
    root: Path,
    source_directory: str,
    destination_directory: str,
    exclusions: tuple[str, ...] = (),
) -> list[tuple[str, str]]:
    package = root / source_directory
    require(package.is_dir() and not is_reparse_or_mount(package), f"missing safe regular source directory: {source_directory}")
    mapping: list[tuple[str, str]] = []
    candidates: list[Path] = []
    for current_root, directory_names, file_names in os.walk(package, topdown=True, followlinks=False):
        current = Path(current_root)
        safe_directories: list[str] = []
        for name in sorted(directory_names):
            directory = current / name
            relative_directory = directory.relative_to(package).as_posix()
            validate_source_relative_policy(relative_directory)
            require(not is_reparse_or_mount(directory), f"source directory may not be a link, reparse point, junction, or mount: {relative_directory}")
            safe_directories.append(name)
        directory_names[:] = safe_directories
        for name in sorted(file_names):
            candidates.append(current / name)
    for candidate in sorted(candidates, key=lambda item: item.relative_to(package).as_posix()):
        relative = candidate.relative_to(package).as_posix()
        validate_source_relative_policy(relative)
        require(not is_reparse_or_mount(candidate), f"source file may not be a link, reparse point, junction, or mount: {relative}")
        require(stat.S_ISREG(candidate.lstat().st_mode), f"non-regular source entry is forbidden: {relative}")
        if relative in exclusions:
            continue
        source = f"{source_directory}/{relative}"
        destination = f"{destination_directory}/{relative}" if destination_directory else relative
        mapping.append((source, destination))
    require(mapping, f"recursive source mapping is empty: {source_directory}")
    return mapping


def expected_mapping(root: Path) -> list[tuple[str, str]]:
    mapping = [
        *STATIC_MAPPINGS,
        *discover_tree_mapping(root, PACKAGE_DIRECTORY, PACKAGE_DESTINATION, PACKAGE_ONLY_EXCLUSIONS),
        *discover_tree_mapping(root, REPO_OVERLAY_DIRECTORY, ""),
    ]
    mapping.sort(key=lambda item: item[0])
    sources = [source for source, _ in mapping]
    destinations = [destination for _, destination in mapping]
    require(len(sources) == len({path_collision_key(value) for value in sources}), "overlay mapping contains Windows-colliding sources")
    require(len(destinations) == len({path_collision_key(value) for value in destinations}), "overlay mapping contains Windows-colliding destinations")
    for source, destination in mapping:
        validate_relative(source, "overlay source")
        validate_relative(destination, "overlay destination")
        require(not source.startswith("reference/private/"), f"private source is forbidden: {source}")
    return mapping


def file_entry(root: Path, source: str, destination: str) -> dict[str, Any]:
    path = validate_regular_source(root, source)
    body = path.read_bytes()
    return {
        "source": source,
        "destination": destination,
        "sha256": hashlib.sha256(body).hexdigest(),
        "bytes": len(body),
        "mode": INSTALL_MODE,
    }


def build_manifest(root: Path) -> dict[str, Any]:
    # Walk and reject every unsafe directory/file component before parsing any
    # package JSON.  This prevents validation from following a hostile link to
    # an out-of-package JSON document even though the later mapping walk would
    # eventually reject that link.
    mapping = expected_mapping(root)
    validate_all_mapped_json(root, mapping)
    files = [file_entry(root, source, destination) for source, destination in mapping]
    return {
        "manifest_version": MANIFEST_VERSION,
        "policy_id": POLICY_PARITY_MARKER,
        "baseline_id": BASELINE_ID,
        "target_root": TARGET_ROOT,
        "target_branch": TARGET_BRANCH,
        "target_remote": TARGET_REMOTE,
        "mapping_policy": {
            "package_directory": PACKAGE_DIRECTORY,
            "package_destination": PACKAGE_DESTINATION,
            "recursive": True,
            "package_only_exclusions": list(PACKAGE_ONLY_EXCLUSIONS),
            "private_sources_allowed": False,
            "install_mode": INSTALL_MODE,
            "repo_overlay_directory": REPO_OVERLAY_DIRECTORY,
            "repo_overlay_destination": ".",
            "repo_overlay_recursive": True,
        },
        "file_count": len(files),
        "files": files,
    }


def canonical_bytes(manifest: dict[str, Any]) -> bytes:
    return (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=False) + "\n").encode("utf-8")


def write_atomic(path: Path, body: bytes) -> None:
    require(not path.is_symlink(), "overlay-manifest.json may not be a symbolic link")
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".overlay-manifest.", suffix=".tmp", dir=path.parent, delete=False) as handle:
            temporary_name = handle.name
            handle.write(body)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, path)
        temporary_name = None
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true", help="reject any byte-level drift from the canonical manifest")
    action.add_argument("--write", action="store_true", help="atomically regenerate overlay-manifest.json")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    manifest_path = root / "overlay-manifest.json"
    try:
        require(root.is_dir(), f"package root does not exist: {root}")
        manifest = build_manifest(root)
        expected = canonical_bytes(manifest)
        if args.check:
            require(manifest_path.is_file() and not manifest_path.is_symlink(), "overlay-manifest.json is missing or unsafe")
            actual = manifest_path.read_bytes()
            require(actual == expected, "overlay-manifest.json is not the exact canonical recursive manifest; run with --write")
            print(f"PASS [OVERLAY_MANIFEST]: {len(manifest['files'])} exact recursive overlay entries")
        else:
            write_atomic(manifest_path, expected)
            print(f"PASS [OVERLAY_MANIFEST]: wrote {len(manifest['files'])} exact recursive overlay entries")
    except (ManifestError, OSError, UnicodeError, ValueError) as exc:
        print(f"FAIL [OVERLAY_MANIFEST]: {exc}", file=sys.stderr)
        print("RESULT: FAIL")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
