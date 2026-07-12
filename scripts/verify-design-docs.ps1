$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$designRoot = Join-Path $root "docs\design"
$failed = $false
function Fail([string]$m){ Write-Host "FAIL: $m"; $script:failed = $true }
function Pass([string]$m){ Write-Host "PASS: $m" }
function ReadText([string]$p){ [System.IO.File]::ReadAllText($p,[System.Text.Encoding]::UTF8) }
function U([int[]]$c){ [string]::Concat(($c | ForEach-Object { [char]$_ })) }
$required = @(
"README.md",
"00-governance\DOC-001-document-control.md","00-governance\DOC-002-terminology.md","00-governance\DOC-003-design-principles.md","00-governance\DOC-004-design-decisions.md",
"01-requirements\REQ-001-system-requirements.md","01-requirements\REQ-002-non-functional-requirements.md","01-requirements\REQ-003-requirements-traceability.md",
"02-system\SYS-001-system-design-description.md","02-system\SYS-002-system-context.md","02-system\SYS-003-logical-architecture.md","02-system\SYS-004-runtime-data-flow.md","02-system\SYS-005-deployment-architecture.md","02-system\SYS-006-development-system.md",
"03-components\CDD-001-frontend.md","03-components\CDD-002-backend-api.md","03-components\CDD-003-authentication.md","03-components\CDD-004-cms.md","03-components\CDD-005-search.md","03-components\CDD-006-storage.md","03-components\CDD-007-audit-observability.md","03-components\CDD-008-database.md",
"04-interfaces\ICD-001-api-interface.md","04-interfaces\ICD-002-database-interface.md","04-interfaces\ICD-003-file-storage-interface.md","04-interfaces\ICD-004-email-interface.md","04-interfaces\ICD-005-error-catalog.md",
"05-security\SEC-001-security-architecture.md","05-security\SEC-002-threat-model.md","05-security\SEC-003-privacy-design.md",
"06-operations\OPS-001-configuration.md","06-operations\OPS-002-deployment.md","06-operations\OPS-003-logging-monitoring.md","06-operations\OPS-004-backup-recovery.md","06-operations\OPS-005-operations-runbook.md",
"07-verification\VER-001-verification-strategy.md","07-verification\VER-002-test-design.md","07-verification\VER-003-acceptance-criteria.md","07-verification\VER-004-quality-gates.md",
"08-review\CDR-001-review-package.md","08-review\CDR-002-checklist.md","08-review\CDR-003-risk-analysis.md","08-review\CDR-004-review-record.md")
foreach($r in $required){ if(-not(Test-Path -LiteralPath (Join-Path $designRoot $r))){ Fail "missing required document $r" } }
if(-not $failed){ Pass "required design documents exist" }
$files = Get-ChildItem -LiteralPath $designRoot -Recurse -File -Filter "*.md"
if($files.Count -ne $required.Count){ Fail "expected $($required.Count) Markdown files under docs/design, found $($files.Count)" } else { Pass "docs/design Markdown file count is $($files.Count)" }
$allText = ($files | ForEach-Object { ReadText $_.FullName }) -join "`n"
$banned = @("IMPLEMENTED-RC1","IMPLEMENTED-UNVERIFIED","PLANNED-RC2","ENVIRONMENT-BLOCKED","As-Is","To-Be",(U @(0xD604,0xC7AC,0x20,0xBBF8,0xAD6C,0xD604)),("Docker "+(U @(0xBBF8,0xC124,0xCE58))),(U @(0xD604,0xC7AC,0x20,0xD14C,0xC2A4,0xD2B8,0x20,0xACB0,0xACFC)),"current implementation status","implementation status matrix","as-built")
foreach($p in $banned){ if($allText -match [regex]::Escape($p)){ Fail "prohibited phrase found in docs/design: $p" } }
$placeholders = @("TBD","TODO","fill in","empty placeholder")
foreach($p in $placeholders){ if($allText -match $p){ Fail "placeholder marker found in docs/design: $p" } }
if($allText -match "[A-Za-z]:\\|/Users/|/home/|/mnt/|/workspace/"){ Fail "local absolute path found in docs/design" } else { Pass "local absolute paths absent" }
$docIds = @(); foreach($f in $files){ foreach($m in [regex]::Matches((ReadText $f.FullName),"(?m)^#\s+([A-Z]{2,4}-\d{3})\b")){ $docIds += $m.Groups[1].Value } }
$dDoc = $docIds | Group-Object | Where-Object Count -gt 1; if($dDoc){ Fail "duplicate document IDs: $($dDoc.Name -join ', ')" } else { Pass "document IDs are unique" }
$reqIds = @(); foreach($r in @("01-requirements\REQ-001-system-requirements.md","01-requirements\REQ-002-non-functional-requirements.md")){ foreach($m in [regex]::Matches((ReadText (Join-Path $designRoot $r)),"(?m)^\|\s*(REQ-(?:F|NF)-\d{3})\s*\|")){ $reqIds += $m.Groups[1].Value } }
$dReq = $reqIds | Group-Object | Where-Object Count -gt 1; if($dReq){ Fail "duplicate requirement IDs: $($dReq.Name -join ', ')" } else { Pass "requirement IDs are unique" }
$traceText = ReadText (Join-Path $designRoot "01-requirements\REQ-003-requirements-traceability.md")
foreach($id in $reqIds){ if($traceText -notmatch [regex]::Escape($id)){ Fail "requirement missing from traceability matrix: $id" } }
if(-not $failed){ Pass "requirements trace to design and verification" }
$cddHeadings = @("## 1. Purpose","## 2. Scope","## 3. Responsibilities","## 4. Non-Responsibilities","## 5. Components","## 6. Provided Interfaces","## 7. Consumed Interfaces","## 8. Dependencies","## 9. Data Structures","## 10. Normal Processing","## 11. Error And Exception Handling","## 12. State And Lifecycle","## 13. Concurrency And Transactions","## 14. Security Controls","## 15. Configuration","## 16. Performance","## 17. Scalability","## 18. Observability","## 19. Testability","## 20. Design Decisions")
Get-ChildItem -LiteralPath (Join-Path $designRoot "03-components") -File -Filter "CDD-*.md" | ForEach-Object { $t=ReadText $_.FullName; foreach($h in $cddHeadings){ if($t -notmatch [regex]::Escape($h)){ Fail "missing CDD heading '$h' in $($_.Name)" } } }
if(-not $failed){ Pass "CDD common headings are present" }
$databaseText = ReadText (Join-Path $designRoot "04-interfaces\ICD-002-database-interface.md")
foreach($e in @("User","RolePolicy","RefreshSession","PasswordResetToken","Category","Tag","Resource","ResourceAttachment","Notice","Article","FAQ","Inquiry","Bookmark","AuditLog","FileObject","EmailDelivery")){ if($databaseText -notmatch [regex]::Escape($e)){ Fail "database interface missing entity $e" } }
if(-not $failed){ Pass "target data model includes required entities" }
foreach($f in $files){ if((([regex]::Matches((ReadText $f.FullName),'```')).Count % 2) -ne 0){ Fail "unbalanced Markdown code fence in $($f.Name)" } }
if(-not $failed){ Pass "Markdown code fences are balanced" }
$linkRegex = "\[[^\]]+\]\((?!https?://|mailto:|#)([^)#]+)(?:#[^)]+)?\)"
foreach($f in $files){ foreach($m in [regex]::Matches((ReadText $f.FullName),$linkRegex)){ $target=$m.Groups[1].Value; if($target.StartsWith("/")){ Fail "absolute Markdown link found in $($f.Name): $target" } elseif(-not(Test-Path -LiteralPath (Join-Path $f.DirectoryName $target))){ Fail "broken relative Markdown link in $($f.Name): $target" } } }
if(-not $failed){ Pass "relative Markdown links are valid" }
$designReadme = ReadText (Join-Path $designRoot "README.md")
foreach($r in $required){
  $slash = $r -replace "\\", "/"
  if($slash -eq "README.md"){ continue }
  if($designReadme -notmatch [regex]::Escape($slash)){ Fail "document not linked from docs/design/README.md: $slash" }
}
if(-not $failed){ Pass "docs/design README links every required document" }
$rootReadme = ReadText (Join-Path $root "README.md")
if($rootReadme -notmatch [regex]::Escape("docs/design/README.md")){ Fail "root README does not link docs/design/README.md" }
if($rootReadme -notmatch [regex]::Escape(".\scripts\verify-design-docs.ps1")){ Fail "root README does not show design-doc verification command" }
if(-not $failed){ Pass "root README links to design package and verifier" }
$agentsText = ReadText (Join-Path $root "AGENTS.md")
foreach($needle in @("ICD-001-api-interface.md","CDD-008-database.md","CDD-003-authentication.md","CDD-006-storage.md","SYS-005-deployment-architecture.md","REQ-003-requirements-traceability.md","verify-design-docs.ps1")){
  if($agentsText -notmatch [regex]::Escape($needle)){ Fail "AGENTS.md missing design maintenance rule reference: $needle" }
}
if(-not $failed){ Pass "AGENTS design maintenance rules are present" }
$cdrText = ReadText (Join-Path $designRoot "08-review\CDR-004-review-record.md")
foreach($conditionId in @("PC-001","PC-002","PC-003","PC-004","PC-005","PC-006","PC-007","PC-008","PC-009")){
  if($cdrText -notmatch [regex]::Escape($conditionId)){ Fail "CDR condition missing: $conditionId" }
}
foreach($field in @("Decision owner role","Affected documents","Required evidence","Exit criteria")){
  if($cdrText -notmatch [regex]::Escape($field)){ Fail "CDR condition field missing: $field" }
}
if(-not $failed){ Pass "CDR condition IDs and exit fields are present" }
if($failed){ Write-Host "RESULT: FAIL"; exit 1 }
Write-Host "RESULT: PASS"; exit 0