"""Replaceable document parsing and grounded lexical retrieval boundaries."""

import hashlib
import io
import re
import zipfile
from dataclasses import dataclass


@dataclass(frozen=True)
class ParsedNode:
    ordinal: int
    node_type: str
    heading: str
    content: str
    locator: str


class DocumentProcessingError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def checksum(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def _clean_markup(value: str) -> str:
    value = re.sub(r"<[^>]+>", " ", value)
    value = value.replace("&lt;", "<").replace("&gt;", ">")
    return re.sub(r"\s+", " ", value).strip()


def extract_text(content: bytes, mime_type: str, filename: str = "") -> tuple[str, str]:
    normalized = mime_type.lower()
    if normalized in {"text/plain", "text/markdown", "text/html"} or filename.lower().endswith(
        (".txt", ".md", ".html", ".htm")
    ):
        return content.decode("utf-8", errors="replace"), "text-boundary.v1"
    if normalized in {"application/hwpx", "application/x-hwpx"} or filename.lower().endswith(".hwpx"):
        try:
            with zipfile.ZipFile(io.BytesIO(content)) as archive:
                names = sorted(
                    name for name in archive.namelist() if name.startswith("Contents/section")
                )
                if not names:
                    raise DocumentProcessingError("HWPX_SECTION_MISSING", "HWPX section content is missing")
                sections = [
                    _clean_markup(archive.read(name).decode("utf-8", errors="replace")) for name in names
                ]
                return "\n".join(section for section in sections if section), "hwpx-native.v1"
        except zipfile.BadZipFile as exc:
            raise DocumentProcessingError("HWPX_INVALID", "HWPX package is invalid") from exc
    if normalized == "application/pdf" or filename.lower().endswith(".pdf"):
        raise DocumentProcessingError("PDF_ADAPTER_REQUIRED", "PDF conversion requires an isolated adapter")
    raise DocumentProcessingError("UNSUPPORTED_MIME", "This document type is not supported by the local parser")


def to_nodes(text: str, max_chars: int = 1200) -> list[ParsedNode]:
    paragraphs = [re.sub(r"\s+", " ", item).strip() for item in text.splitlines()]
    paragraphs = [item for item in paragraphs if item]
    nodes: list[ParsedNode] = []
    ordinal = 0
    for paragraph in paragraphs:
        for start in range(0, len(paragraph), max_chars):
            chunk = paragraph[start : start + max_chars]
            nodes.append(
                ParsedNode(
                    ordinal=ordinal,
                    node_type="paragraph",
                    heading="",
                    content=chunk,
                    locator=f"paragraph:{ordinal}",
                )
            )
            ordinal += 1
    return nodes


def node_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def lexical_score(query: str, content: str) -> int:
    query_terms = {term for term in re.findall(r"[\w가-힣]+", query.lower()) if len(term) > 1}
    content_terms = set(re.findall(r"[\w가-힣]+", content.lower()))
    if not query_terms:
        return 0
    return int(len(query_terms & content_terms) * 1_000_000 / len(query_terms))
