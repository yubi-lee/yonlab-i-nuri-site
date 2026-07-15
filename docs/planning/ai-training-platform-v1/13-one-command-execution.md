# 13. 한 명령 실행·검토·수용 설계

문서 ID: CODEX-RUN-013
규범 기준: `design-baseline.json`, `codex-output.schema.json`, `codex-final-result.schema.json`, `final-document-inventory.json`, `release-trust.example.json`

## 1. 목적과 상태 소유권

Windows의 기존 Git checkout을 임의로 바꾸지 않고 YOnLab AI 연수 플랫폼을 한 번에 구현하되, 구현 주체와 승인 주체를 분리한다. runner는 다음 네 mode만 제공한다.

| Mode | 변경 권한 | 입력 | 유일하게 판정 가능한 상태 |
|---|---|---|---|
| `Implement` | Codex가 feature checkout을 구현·시험·commit·push하고 draft PR을 갱신할 수 있음 | 계획 원천, pinned tool·workflow policy | 항상 `release_state=NOT_READY`; 별도 `candidate_phase=IMPLEMENTATION_BLOCKED` 또는 `UNSIGNED_CANDIDATE / REVIEW PENDING` |
| `VerifyCandidate` | read-only. checkout·index·refs·PR·workflow·tag·attestation을 만들거나 바꾸지 않음 | release snapshot `R`, 외부 technical/artifact signature bundle | `CODE_COMPLETE / ACCEPTANCE DATA PENDING` 또는 검증 실패 |
| `VerifyAccepted` | read-only. `VerifyCandidate` 검증에 수용 승인과 기존 signed tag 검증만 추가 | 위 입력 + OWN-ACC + 기존 signed annotated tag | `ACCEPTED` 또는 검증 실패 |
| `PolicySelfTest` | production runner의 정책 함수를 fixture에 직접 적용하며 repository·network를 변경하지 않음 | 단일 adversarial fixture | 해당 정책의 PASS 또는 fail-closed 거부 |

Codex는 `CODE_COMPLETE / ACCEPTANCE DATA PENDING`이나 `ACCEPTED`를 자기 판정할 수 없다. 두 상태는 외부 보호 입력을 읽기 전용으로 검증한 runner만 판정한다. `VerifyCandidate`와 `VerifyAccepted`는 Codex·Docker·test를 다시 실행하지 않고, repository object와 live GitHub 사실 및 외부 서명을 검증한다. read-only mode는 결과를 console에만 출력하고 tracked receipt나 repository-local 검증 receipt를 만들지 않는다.

## 2. 구현 commit `S`와 release snapshot commit `R`

release identity는 서로 다른 full 40-hex Git commit 두 개다.

- `S`(implementation commit): 전체 구현, migration, test, 구성, 실행 스크립트와 구현 시험 결과의 기준이다. tracked artifact manifest, checksum, evidence index, source provenance는 `S`, `S`의 tree OID 및 `source-tree-hash.v1` SHA-256에 결속한다.
- `R`(release snapshot commit): 최종 문서·운영·QA·매뉴얼·릴리스·배포 문서만 정리한 snapshot이다. 부모가 정확히 하나이며 `R^1 == S`이고 first-parent 관계도 `S → R`이어야 한다. `R != S`다.
- `S..R`의 모든 changed path는 아래 여섯 root 아래의 nonempty, tracked, non-reparse regular file이어야 한다.

```text
docs/design/ai-training-platform/
docs/operations/ai-training-platform/
docs/qa/ai-training-platform/
docs/manuals/ai-training-platform/
docs/releases/ai-training-platform/
dist/docs/
```

artifact/evidence가 생성 중인 `R`을 자신의 source identity로 기록하면 고정점을 만들 수 없으므로 금지한다. tracked file에는 `R` OID, release tag, PR URL, workflow run URL, 외부 승인 receipt 또는 detached signature를 넣지 않는다. `R`은 model result의 `repository.release_snapshot_commit`과 보호된 외부 attestation subject에서만 결속한다. runner는 `S`가 실행 기준 commit의 후손인지, `R`의 유일한 direct first parent가 `S`인지, allowlist 밖 diff가 0인지, artifact/evidence의 모든 source field가 `S`인지 독립 검증한다.

## 3. 정식 명령과 exit 의미

설계 overlay를 설치·검토·commit한 뒤 `D:\Views\yonlab-inuri-site`에서 구현한다.

```powershell
$runnerHost = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
& $runnerHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1' -Mode Implement
```

preflight와 계약만 확인한다.

```powershell
$runnerHost = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
& $runnerHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1' -Mode Implement -DryRun
```

외부 검토가 끝난 candidate를 읽기 전용으로 검증한다.

```powershell
$runnerHost = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
& $runnerHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1' `
  -Mode VerifyCandidate `
  -AttestationBundlePath 'C:\ProgramData\YOnLab\attestations\<release-id>\attestation-bundle.json'
```

발주기관 수용과 signed tag까지 이미 준비된 release를 읽기 전용으로 검증한다.

```powershell
$runnerHost = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
& $runnerHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1' `
  -Mode VerifyAccepted `
  -AttestationBundlePath 'C:\ProgramData\YOnLab\attestations\<release-id>\attestation-bundle.json'
```

runner exit 의미는 다음과 같다.

| Exit | 의미 |
|---:|---|
| `0` | `VerifyCandidate` 또는 `VerifyAccepted`의 모든 필수 검증 통과 |
| `2` | 호출 전 정책/preflight 실패, 어떤 변경 작업도 시작하지 않음 |
| `3` | 필수 platform/tool 기능이 없어 검증 불가 |
| `5` | `Implement` 결과. `release_state=NOT_READY`이며 `candidate_phase`는 `IMPLEMENTATION_BLOCKED` 또는 검증이 끝난 `UNSIGNED_CANDIDATE / REVIEW PENDING` |
| `6` | post-run identity, evidence, CI, signature 또는 tag 불일치 |

`Implement`는 exit `0`으로 승인 완료를 주장하지 않는다. 자동화는 exit `5`와 console의 `CANDIDATE_PHASE`를 함께 읽어 구현 차단과 외부 검토 대기 candidate를 구분한다. 승인 상태는 오직 두 read-only verification mode의 exit `0`으로만 성립한다.

## 4. 최초 overlay 설치

압축 패키지 root에서 변경 예정 파일을 먼저 확인한 뒤 manifest에 열거된 파일만 설치한다.

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\start-ai-training-platform-v1.ps1 -InstallOverlay -DryRun
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\start-ai-training-platform-v1.ps1 -InstallOverlay
```

설치기는 압축 해제 후 패키지 내부의 source SHA-256, destination allowlist, 경로 순회, duplicate path, reparse point, exact checkout, clean worktree를 fail-closed 검증한다. 이 검증은 “추출된 파일끼리 manifest와 일치한다”는 내부 일관성만 증명하며, 배포 ZIP 자체의 진본성·출처·전송 중 무결성을 증명하지 않는다. 운영자는 공급자가 별도 채널로 전달한 ZIP SHA-256 또는 detached signature를 **압축 해제 전에** 대조한 뒤 설치해야 한다. ZIP 안에 같이 들어 있는 checksum만으로 ZIP을 신뢰하지 않는다. 기존 파일 backup과 overlay receipt는 `.artifacts/codex/overlay-backups/`에만 남긴다. backup·staging·설치 byte stream은 `FileStream.Flush(true)`를 완료한 뒤에만 transaction journal을 `PREPARED` 또는 `COMMITTED`로 전이한다. temporary와 destination은 같은 NTFS volume에 두며 atomic rename을 directory metadata 경계로 사용하고, 불완전 journal은 다음 실행을 차단한다. 설치와 구현은 자동으로 연속 실행하지 않는다. 사람이 diff를 검토하고 overlay를 commit한 후에만 `Implement`를 실행한다. bootstrap은 branch 생성·전환, fetch, rebase, reset, commit, push를 수행하지 않는다.

## 5. 보호된 실행 기반

production mode는 첫 repository/trust read보다 먼저 active process를 검사한다. host는 `[Environment]::SystemDirectory\WindowsPowerShell\v1.0\powershell.exe` 하나만 허용하며 argv 0~7은 `powershell.exe`, `-NoLogo`, `-NoProfile`, `-NonInteractive`, `-ExecutionPolicy`, `Bypass`, `-File`, absolute current runner path의 exact prefix여야 한다. 이후 인자만 runner parameter다. user-installed `pwsh.exe`, wrapper, relative `-File`, option 순서 변경·축약·중복, `-Command`, `-EncodedCommand`, `-NoExit`, `-PSConsoleFile`, `-Version`, unknown pre-File option은 모두 `PRE-HOST`에서 실패한다. cross-platform adversarial fixture를 실행하는 `PolicySelfTest`만 이 production host 검사를 명시적으로 생략하며 repository/network mutation 권한은 없다. trust store의 `trusted_tools.powershell.path`도 같은 OS PowerShell 경로를 가리켜야 이후 active-process path/hash/ACL 재검증이 구성 가능하다.

### 5.1 direct trusted executables

ambient `PATH`, alias, function, `.cmd`/`.bat` shim, repository-local binary와 custom wrapper는 신뢰하지 않는다. 관리자는 승인된 direct executable 7개(`powershell`, `python`, `git`, `gh`, `docker`, `codex`, `gpg`)의 실제 설치 경로를 `release-trust.v2`에 기록한다. 공백과 괄호는 올바르게 quote된 canonical Windows 경로에서 허용하지만 따옴표·역따옴표·환경변수 표식·command separator·redirection 등 shell metacharacter, ADS와 dot segment는 금지한다. 허용 root는 다음으로 닫는다.

```text
%SystemRoot%\...
%ProgramFiles%\...
%ProgramFiles(x86)%\...
C:\ProgramData\YOnLab\bin\...
```

user profile과 raw `%LOCALAPPDATA%`는 user-writable이므로 허용 root가 아니다. 각 executable은 `release-trust.v2`의 exact absolute path와 SHA-256이 일치하고, executable에서 volume root까지의 경로 chain이 non-reparse이며 owner가 `SYSTEM`·`Administrators`·`TrustedInstaller` 중 하나여야 한다. executable부터 승인 설치 root까지는 일반 사용자·`Users`·`Everyone`·`Authenticated Users`의 write/modify/delete/control을 금지하고, 그 위 volume root까지는 `DELETE_CHILD`, delete, ACL 변경, ownership 탈취처럼 승인 root를 교체할 수 있는 권한을 금지한다. `authenticode_required=true`인 tool만 `Valid` status와 exact signer thumbprint가 필수다. `false`인 tool은 `authenticode_signer_thumbprint=null`이어야 하며 SHA-256과 ACL 검증은 그대로 필수다. runner는 시작 전, Codex 종료 직후, 최종 판정 직전에 path·hash·conditional signer·ACL을 다시 읽는다. 실행 중 값이 바뀌면 즉시 실패한다. tool path와 trust file hash는 run/resume identity에 포함한다.

GitHub credential helper는 고정된 direct `gh.exe`에 붙는 exact 문자열 하나만 child Git config에 허용한다.

```text
!"C:/Program Files/GitHub CLI/gh.exe" auth git-credential
```

위 double quote를 포함한 한 문자열과 같은, trust에 기록된 `gh.exe` absolute path에서 계산한 exact helper만 허용한다. 가변 suffix·다른 shell command는 허용하지 않는다. `gpg.program`도 trust의 canonical `gpg.exe` path를 double quote한 exact 값만 허용한다. `http.extraHeader`, `http.sslVerify=false`, SSL cert/key override, cookie, username, URL rewrite, proxy, 임의 credential helper를 포함한 ambient Git config는 호출 전에 거부한다.

`Invoke-NativeCaptureBytes`, `Invoke-TrustedValidatorProcess`, `Invoke-Utf8Process`가 만드는 모든 `ProcessStartInfo`는 `WorkingDirectory`를 해당 direct executable의 canonical parent directory로 고정한다. repository나 caller CWD를 상속하지 않으므로 current-directory DLL search를 이용한 side-loading을 차단한다. Git은 모든 repository 연산에 explicit `-C D:\Views\yonlab-inuri-site`를 사용하고, validator·GPG·Codex의 파일 인자는 absolute path 또는 자체 `-C` 계약으로 전달한다.

### 5.2 release trust와 public-only GPG

보호 경로는 다음과 같이 고정한다.

```text
C:\ProgramData\YOnLab\release-trust.json
C:\ProgramData\YOnLab\empty-git-hooks\
C:\ProgramData\YOnLab\gnupg\
C:\ProgramData\YOnLab\attestations\<release-id>\
```

`release-trust.json`은 `schema_version=release-trust.v2`, repository, attestation root, exact 8 owner fingerprint, OWN-QA tag signer, exact 7 trusted tools, GitHub actor/workflow policy를 가진다. 각 tool record는 `path`, `sha256`, `authenticode_required`, `authenticode_signer_thumbprint` 네 필드만 가진다. example은 의도적으로 실행 불가능한 placeholder template이며 workspace 사본을 실제 trust로 쓸 수 없다.

위 네 보호 경로는 단순히 leaf ACL만 확인하지 않는다. 각 보호 root와 root 내부의 모든 intermediate/leaf는 reparse point가 아니어야 하고 owner가 `SYSTEM`·`Administrators`·`TrustedInstaller` 중 하나여야 하며, 다른 SID에 적용되는 write/modify/delete/create/control Allow ACE가 없어야 한다. 보호 root의 부모부터 volume root까지도 같은 trusted owner 정책을 적용하고, 다른 SID의 `DeleteSubdirectoriesAndFiles(DELETE_CHILD)`, `Delete`, `ChangePermissions`, `TakeOwnership`, `FullControl`을 거부한다. 따라서 공격자가 자신이 소유한 `release-trust.json` leaf를 만들어 놓거나 부모의 `DELETE_CHILD`로 안전해 보이는 leaf를 바꾸는 경우 preflight에서 실패한다.

runner는 release trust file bytes, empty hooks tree, public-only GPG tree, attestation tree의 경로·owner·ACL SDDL·file length·SHA-256을 bounded snapshot으로 만든다. Codex 종료 직후와 최종 판정 직전, read-only verification의 외부 서명 사용 직후에 전 경로 chain과 snapshot을 다시 계산한다. bundle, candidate result, approval subject, detached signature는 사용 전후 SHA-256도 별도로 대조한다. 어느 root, intermediate, leaf 또는 byte가 바뀌면 `POST-TRUST`/`EXTERNAL-ATTESTATION`으로 fail-closed하며 승인 상태를 출력하지 않는다.

GPG home은 public-key-only다. `private-keys-v1.d`, `openpgp-revocs.d`, secret key, reparse point와 broad ACL이 없어야 한다. approved public key를 가져오는 올바른 명령은 input redirection이 아니라 명시적 파일 인자다.

```powershell
$trustedGpg = 'C:\Program Files (x86)\GnuPG\bin\gpg.exe'
$gpgHome = 'C:\ProgramData\YOnLab\gnupg'
& $trustedGpg --homedir $gpgHome --no-options --batch --no-tty --import .\approved-public-keys.asc
& $trustedGpg --homedir $gpgHome --no-options --batch --no-tty --check-trustdb
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[IO.File]::WriteAllText((Join-Path $gpgHome 'gpg.conf'), "no-auto-check-trustdb`n", $utf8NoBom)
if (-not (Test-Path -LiteralPath (Join-Path $gpgHome 'trustdb.gpg') -PathType Leaf) -or (Get-Item -LiteralPath (Join-Path $gpgHome 'trustdb.gpg')).Length -le 0) { throw 'preprovisioned trustdb.gpg is required' }
& $trustedGpg --homedir $gpgHome --no-options --no-auto-key-retrieve --no-auto-check-trustdb --batch --no-tty --with-colons --fingerprint --list-keys
```

위 단계는 보호 ACL 적용 전의 별도 provisioning 절차다. 이후 `gpg.conf`는 UTF-8 BOM 없이 exact byte text `no-auto-check-trustdb\n` 하나만 가져야 하고 `trustdb.gpg`는 non-empty regular file이어야 한다. 추가 option, comment, blank line, BOM, 누락되거나 빈 trustdb를 허용하지 않는다.

runner child process는 `GNUPGHOME=C:\ProgramData\YOnLab\gnupg`를 고정하고 direct GPG에 `--no-options --no-auto-key-retrieve --no-auto-check-trustdb --batch --no-tty`를 사용한다. Git `verify-tag`는 direct executable만 지정하므로 보호된 `gpg.conf`의 exact `no-auto-check-trustdb`를 읽는다. runner는 최초 GPG 실행 전 tree/ACL snapshot을 만들고, 각 direct GPG call과 Git `verify-tag` 직후 다시 계산한다. lock, trustdb, config, keyring을 포함한 persistent byte·path·SDDL 변화가 있으면 `POST-GPG` 또는 `POST-TAG-GPG`로 실패한다. detached signature와 tag의 `VALIDSIG`는 trusted fingerprint, EdDSA/Ed25519 public-key algorithm `22`, SHA-256 hash algorithm `8`과 정확히 일치해야 한다. private key를 읽거나 서명하지 않는다.

### 5.2.1 공개키 fingerprint 수집과 release-trust 반영

GPG 설치 여부는 다음 두 명령으로 확인한다. 둘 다 실패하면 설치를 자동 수행하지 않고 운영자 승인을 먼저 받는다.

~~~
gpg --version
where.exe gpg
~~~

승인된 설치가 필요할 때만 다음 명령을 사람이 실행한다. 이 작업은 private key를 만들거나 저장하지 않는다.

~~~
winget install GnuPG.GnuPG
~~~

C:\ProgramData\YOnLab\gnupg는 public-only verification home이다. 운영 공개키 bundle은 repository 밖의 승인된 전달 경로로 받아 import하며, approved-public-keys.asc와 private key는 repo에 넣지 않는다.

~~~
$trustedGpg = 'C:\Program Files (x86)\GnuPG\bin\gpg.exe'
$gpgHome = 'C:\ProgramData\YOnLab\gnupg'
& $trustedGpg --homedir $gpgHome --no-options --batch --no-tty --import .\approved-public-keys.asc
& $trustedGpg --homedir $gpgHome --no-options --batch --no-tty --with-colons --fingerprint --list-keys
& $trustedGpg --homedir $gpgHome --no-options --batch --no-tty --with-colons --list-secret-keys
& $trustedGpg --homedir $gpgHome --no-options --batch --no-tty --check-trustdb
~~~

with-colons 출력의 fpr: record에서 field 10을 수집한다. sec: record가 하나라도 있으면 verification-only home으로 사용할 수 없다. fingerprint는 공개값이지만, 역할 배정은 외부 승인 기록과 함께 수행한다.

| release-trust field | 승인 대상 |
|---|---|
| owner_fingerprints.OWN-ARCH | Architecture owner public key |
| owner_fingerprints.OWN-UX | UX owner public key |
| owner_fingerprints.OWN-AI | AI owner public key |
| owner_fingerprints.OWN-DOC | Documentation owner public key |
| owner_fingerprints.OWN-SEC | Security owner public key |
| owner_fingerprints.OWN-OPS | Operations owner public key |
| owner_fingerprints.OWN-QA | QA owner public key |
| owner_fingerprints.OWN-ACC | Acceptance owner public key |
| tag_signer_fingerprint | 반드시 OWN-QA와 같은 fingerprint |

각 owner 값은 서로 다른 40/64자리 hexadecimal fingerprint여야 한다. tag_signer_fingerprint는 별도 임의 키가 아니라 exact OWN-QA 값이어야 한다.

운영 ACCEPTED와 개발 PRE-TRUST는 분리한다. 개발 검증에 사용할 수 있는 것은 별도 관리되는 dev public key뿐이며, 그 fingerprint는 PRE-TRUST 전진 확인용이지 운영 owner 또는 release signer의 ACCEPTED 증명이 아니다. private key 생성·반입·저장 없이 이미 승인된 dev public key를 import하는 경우에만 사용하고, dev fingerprint를 운영 release-trust에 그대로 승격하지 않는다.

실제 fingerprint가 모두 준비되기 전에는 C:\ProgramData\YOnLab\release-trust.json을 수정하지 않는다. 준비가 끝난 승인된 provisioning window에서만 다음 guarded 절차를 실행한다. 이 절차는 owner 8개와 tag signer만 갱신하며 tool hash와 GitHub workflow policy는 별도 승인 입력으로 유지한다.

~~~
$ErrorActionPreference = 'Stop'
$trustPath = 'C:\ProgramData\YOnLab\release-trust.json'
$roles = @('OWN-ARCH','OWN-UX','OWN-AI','OWN-DOC','OWN-SEC','OWN-OPS','OWN-QA','OWN-ACC')
$owner = [ordered]@{}
$seen = @{}
$trustedGpg = 'C:\Program Files (x86)\GnuPG\bin\gpg.exe'
$gpgHome = 'C:\ProgramData\YOnLab\gnupg'
if (-not (Test-Path -LiteralPath $trustedGpg -PathType Leaf)) { throw 'approved GPG executable is missing' }
$keyInventory = @(& $trustedGpg --homedir $gpgHome --no-options --batch --no-tty --with-colons --fingerprint --list-keys)
if ($LASTEXITCODE -ne 0) { throw 'public-key inventory failed' }
if (@($keyInventory | Where-Object { ([string]$_).StartsWith('sec:', [StringComparison]::Ordinal) }).Count -ne 0) { throw 'verification-only GPG home contains secret-key material' }
$availableFingerprints = @($keyInventory | ForEach-Object { $line = [string]$_; if ($line.StartsWith('fpr:', [StringComparison]::Ordinal)) { $fields = $line -split ':'; if ($fields.Count -gt 9) { $fields[9].ToUpperInvariant() } } } | Where-Object { $_ } | Sort-Object -Unique)
foreach ($role in $roles) {
    $fingerprint = (Read-Host "Approved public-key fingerprint for $role").Trim().ToUpperInvariant()
    if ($fingerprint -notmatch '^[0-9A-F]{40}([0-9A-F]{24})?$') { throw "$role must be an approved 40/64-hex fingerprint" }
    if ($seen.ContainsKey($fingerprint)) { throw "duplicate owner fingerprint: $role" }
    $owner[$role] = $fingerprint
    $seen[$fingerprint] = $role
}
foreach ($fingerprint in $owner.Values) { if ($availableFingerprints -notcontains $fingerprint) { throw 'public-key keyring lacks an approved owner fingerprint' } }
$trust = Get-Content -LiteralPath $trustPath -Raw | ConvertFrom-Json
if ([string]$trust.schema_version -cne 'release-trust.v2' -or [string]$trust.repository -cne 'yubi-lee/yonlab-i-nuri-site' -or [string]$trust.attestation_root -cne 'C:\ProgramData\YOnLab\attestations') { throw 'release-trust identity mismatch' }
$trust.owner_fingerprints = [pscustomobject]$owner
$trust.tag_signer_fingerprint = $owner['OWN-QA']
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[IO.File]::WriteAllText($trustPath, (($trust | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8NoBom)
~~~

이 절차의 입력이 없거나 placeholder이면 write하지 않고 현재 release-trust.json을 보존한다. 실제 값 반영 후에도 runner는 trusted tool path/hash/signer, GitHub actor/workflow, public keyring과 attestation을 별도로 검증한다. fingerprint와 trust JSON은 machine-local 보호 경로에만 두며 repo에는 문서와 절차만 commit한다.
### 5.3 외부 workflow prerequisite

required CI workflow는 candidate가 만드는 산출물이 아니다. 조직 관리자가 구현 실행 전에 `main`에 설치하고, 각 workflow의 numeric ID, repository path, `main` content SHA-256, exact check/job name, allowed actor와 required runner label set을 외부 `release-trust.v2`에 고정한다. candidate는 `.github/workflows/`를 추가·수정할 수 없다. `main`에 workflow가 없거나 trust의 ID/path/hash와 다르면 `Implement` 시작 전에 중단한다.

runner는 live GitHub API로 다음을 모두 대조한다.

1. head가 exact `R`인 open non-fork `feat/ai-training-platform-v1 → main` PR이 정확히 하나다.
2. check set과 각 check name은 trust policy와 exact set equality이며 missing, duplicate, extra, pending, skipped, neutral, cancelled, failed check가 없다.
3. 각 run은 exact PR number, trusted workflow numeric ID와 path, `pull_request` event, head `R`, completed/success, allowed actor를 가진다.
4. PR의 exact immutable `base.sha`와 release snapshot `R`에서 workflow 원문을 각각 GitHub contents API로 다시 읽고 두 실제 SHA-256이 모두 외부 trust hash와 정확히 같다. 따라서 candidate가 workflow를 바꾸거나, 일시적 workflow로 성공 check를 만든 뒤 `main`을 되돌려 정책값만 자기보고하는 경우를 허용하지 않는다.
5. 각 job name과 check name이 policy와 일치하고, runner name이 비어 있지 않으며 label set이 required label set과 exact 일치한다. Windows job은 실제 Windows label을 가져야 한다.

tracked evidence에는 PR/check/run URL을 저장하지 않는다. live URL과 run ID는 transient runner evidence에만 기록한다.

### 5.4 관리자 provisioning과 현재 상태

패키지는 실제 fingerprint, secret, tool hash, workflow ID 또는 외부 서명을 포함하지 않는다. 다음 항목은 조직 관리자가 candidate branch 밖에서 먼저 provision하고 별도 변경 기록으로 승인한다.

1. protected `main`에 exact 네 check를 내는 `.github/workflows/release.yml`을 설치하고 workflow numeric ID, immutable source SHA-256, job/check name과 runner label을 게시한다.
2. `release-trust.example.json`을 참고하되 placeholder를 실제 8개 owner public-key fingerprint, 7개 tool absolute path·SHA-256·signer, GitHub actor/workflow 정책으로 교체해 `C:\ProgramData\YOnLab\release-trust.json`에 둔다.
3. `C:\ProgramData\YOnLab` 전체의 owner를 `SYSTEM`·`Administrators`·`TrustedInstaller` 중 하나로 고정하고 inheritance, broad write/delete/control, reparse point를 제거한다. `release-trust.json`, `attestations`, `empty-git-hooks`, `gnupg`와 모든 중간 경로가 같은 full-chain 정책을 만족해야 한다.
4. public-key-only GPG home과 `no-auto-check-trustdb` 정책을 사전 생성하고 trustdb/공개키 import를 끝낸 뒤 ACL을 잠근다. private key는 이 host에 두지 않는다.
5. 외부 owner/QA/수용 서명과 artifact signature는 각 단계가 끝난 후 보호된 attestation root에 별도로 반입한다.

이 provisioning과 조직 승인이 끝나기 전 공식 상태는 `EXTERNAL PREREQUISITES PENDING / NOT_READY`다. placeholder template, workflow ID `0`, 존재하지 않는 workflow, 임시 공개키, workspace 안 trust 사본을 자동 보정하지 않으며 `Implement`도 시작하지 않는다. 후보 branch가 보호 workflow나 root-of-trust를 자기 설치하는 기능은 의도적으로 제공하지 않는다.

## 6. mode별 fail-closed preflight

모든 mode는 exact root·branch·remote·repository, Git control-plane, protected trust/tool inventory, unsafe environment/config 부재, bounded input을 확인한다. `Implement`만 clean worktree, exact upstream 0/0, Codex auth, Docker daemon/Compose, prompt/schema/validator hashes를 추가 요구한다. `VerifyCandidate`와 `VerifyAccepted`는 Codex·Docker를 요구하지 않으며 checkout·index·refs를 변경하는 Git 명령을 호출하지 않는다.

| 코드 | 검증 | 실패 동작 |
|---|---|---|
| `PRE-ROOT` | exact `D:\Views\yonlab-inuri-site`, Git top-level 일치 | exit 2 |
| `PRE-BRANCH` | exact `feat/ai-training-platform-v1` | 자동 switch 없이 exit 2 |
| `PRE-REMOTE` | live repository가 `yubi-lee/yonlab-i-nuri-site` | 자동 수정 없이 exit 2 |
| `PRE-GIT-CONTROL` | config/hooks/attributes/replace/alternate/submodule exact baseline | exit 2 |
| `PRE-GIT-CONFIG` | driver/helper/include/rewrite/proxy/TLS/credential override 0 | exit 2 |
| `PRE-TRUST` | trust v2, tool hash/conditional Authenticode/ACL, public keyring, attestation ACL | exit 2 |
| `PRE-WORKFLOW` | protected `main` workflow ID/path/hash/actor/labels | exit 2 |
| `PRE-IMPLEMENT` | clean/upstream 0/0, Codex auth, Docker, source contracts | exit 2 |
| `PRE-VERIFY` | `R`, external bundle, remote PR/CI are readable; no mutation command | exit 2/6 |

root, planning source, schema, validator, artifact/evidence path, trust/attestation path의 component가 symlink/junction/reparse이면 실패한다. 명령 부재나 native exit code 오류는 이전 `$LASTEXITCODE`를 재사용하지 않는다. native stdout+stderr와 JSON/JSONL/file inventory는 byte budget과 hard timeout을 갖고 overflow/timeout 시 process tree를 종료한다.

## 7. `Implement` 실행과 결과

launcher는 다음 의미의 pinned Codex 호출을 구성하고 11번 문서 전체를 UTF-8 no-BOM 표준입력으로 전달한다.

```text
<trusted-codex> -C D:\Views\yonlab-inuri-site --sandbox workspace-write --ask-for-approval on-request exec --ignore-user-config --ignore-rules --strict-config --json --output-last-message <final-result.json> --output-schema <codex-output.schema.json> -
```

`--dangerously-bypass-approvals-and-sandbox`, `--yolo`, deprecated `--full-auto`, user/project hook 또는 임의 추가 인자는 허용하지 않는다. stdout/stderr는 별도 bounded raw stream으로 동시에 drain하고 hard timeout 때 child tree를 종료한다. heartbeat는 raw evidence를 오염시키지 않는다.

Codex 종료 직후 runner는 어떤 Git 호출보다 먼저 control-plane과 trusted tool inventory를 direct .NET I/O로 재확인한다. 이어서 다음을 독립 검증한다.

- `release_state`는 항상 `NOT_READY`다. 별도 `candidate_phase`만 `IMPLEMENTATION_BLOCKED` 또는 `UNSIGNED_CANDIDATE / REVIEW PENDING`이다.

## Protected trust anchor scope

The canonical protected trust anchor for this platform is `C:\ProgramData\YOnLab`.
The protected targets `release-trust.json`, `attestations`, `gnupg`, and
`empty-git-hooks` must remain below that anchor. For each target, the runner
walks the target and every intermediate component up to and including
`C:\ProgramData\YOnLab`, then stops. `C:\ProgramData` itself and the volume
root are outside this protected-trust scope: the runner does not inspect or
modify their ACLs.

Within the bounded chain, every component remains non-reparse, owned only by
`SYSTEM`, `Administrators`, or `TrustedInstaller`, and free of untrusted
write/modify/delete/create/permission-change/take-ownership/control Allow ACEs.
`release-trust.json` must also remain outside the Codex workspace. Policy
fixtures represent the chain as protected content from the leaf through the
YOnLab anchor; a node above that anchor is invalid. The separate trusted-tool
executable policy may still inspect an approved installation root through the
volume root as documented above; that policy does not authorize changing any
`C:\ProgramData` ACL.

- repository fields는 exact `S`, `S` tree, `source-tree-hash.v1`, `R`이다.
- `R`은 `S`의 single direct first-parent child이고 `S..R`은 여섯 allowlist root만 바꾼다.
- evidence registry의 요구 record set과 evidence-index record set이 exact set equality다. extra/missing/duplicate record가 없다.
- gate/KPI/verification command의 모든 evidence reference는 같은 record의 owner/test/gate/command contract와 호환되고 actual SHA-256가 일치한다.
- final inventory와 artifact manifest/checksum은 `S`와 `S` tree/hash에 결속하며 root content를 전수 coverage한다. tracked file에 `R`, receipt, detached signature 또는 run URL이 없다.
- worktree clean, origin head `R`, exact PR/CI binding이 성립한다.
- technical/artifact/acceptance signature와 release tag가 아직 없다.

두 Implement phase 모두 exit `5`이고 console의 `CANDIDATE_PHASE`가 둘을 구분한다. runner 교차검증 불일치면 exit `6`이다.

## 8. 외부 attestation bundle

외부 검토자는 repository 밖에서 subject JSON과 detached signature를 만들고, 다음 protected directory에 둔다.

```text
C:\ProgramData\YOnLab\attestations\<release-id>\
  attestation-bundle.json
  subjects\*.json
  signatures\*.sig
```

모든 경로는 attestation root 아래의 안전한 relative path로 bundle에 기록한다. attestation root, release ID directory, bundle과 모든 자식은 non-reparse이고 bounded size이며 owner가 `SYSTEM`·`Administrators`·`TrustedInstaller` 중 하나여야 한다. 보호 root 내부에는 이 세 SID 외 write/modify/delete/create/control Allow ACE가 없어야 하고, root 위 volume root까지의 parent chain에도 다른 SID의 `DELETE_CHILD`/delete/ACL-control이 없어야 한다. bundle은 `release-attestation-bundle.v2`, repository, release ID, baseline, `S`, `R`, protected candidate result relative path와 그 actual SHA-256을 정확히 결속한다. candidate result가 담은 `S` tree/hash도 runner가 Git에서 다시 계산한다. tracked manifest나 evidence를 대체하지 않는다.

bundle의 top-level property set은 다음 11개로 닫힌다: `schema_version`, `release_id`, `repository`, `baseline_commit`, `implementation_commit`, `release_snapshot_commit`, `candidate_result_path`, `candidate_result_sha256`, `technical_approvals`, `artifact_signatures`, `acceptance_approval`. extra/missing property, workspace 내부 result path, result hash 불일치는 모두 exit `6`이다.

`VerifyCandidate`에 필요한 입력은 다음과 같다.

- exact 7개 technical approval: `OWN-ARCH`, `OWN-UX`, `OWN-AI`, `OWN-DOC`, `OWN-SEC`, `OWN-OPS`, `OWN-QA`가 각자 고유 scope의 `decision=APPROVED` subject를 서명한다. subject는 `release-approval-subject.v2`이며 exact `S`, `R`, candidate result SHA-256을 포함한다. owner/scope 중복, 공유 signature, 다른 `R` 또는 result binding은 실패한다.
- artifact integrity signature: OWN-QA가 tracked RELEASE/DISTRIBUTION `artifact-manifest.json`과 `SHA256SUMS.txt`의 actual bytes를 각각 서명한다. 네 signature path와 두 artifact scope는 교환할 수 없다.
- `acceptance_approval`은 null이고 release tag는 local/remote 어디에도 없어야 한다. local `show-ref`는 exit 1만 absence로 허용하며, remote 조회는 authenticated GitHub REST의 exact HTTP 404만 absence로 허용한다. 401/403/5xx, network 오류, malformed status는 tag 없음으로 간주하지 않는다.

`VerifyAccepted`는 위 입력 전부에 더해 exact `OWN-ACC`의 `scope_id=FINAL-ACCEPTANCE`, `decision=ACCEPTED` subject와, OWN-QA trusted key로 서명되어 이미 local/remote에 존재하는 annotated tag를 요구한다. tag object와 peeled target은 `R`, tag name/release ID는 bundle, `VALIDSIG`는 trust policy와 일치해야 한다. runner는 tag를 생성·이동·push하지 않는다. local tag는 기존 object만 읽고 remote tag object는 GitHub API로 대조하며, 검증 전후 index·`HEAD`·`refs/heads`·`refs/tags`·`packed-refs` byte snapshot이 정확히 같아야 한다.

외부 bundle에는 private key, token 또는 GitHub run URL을 넣지 않는다. 서명 생성은 runner 범위 밖이며 runner는 public key로만 검증한다.

## 9. read-only verification mode

두 verification mode는 시작과 종료에 worktree, index, `HEAD`, `refs/heads`, `refs/tags`, `packed-refs`와 Git control-plane의 direct byte snapshot을 비교한다. child Git에는 `GIT_OPTIONAL_LOCKS=0`을 고정한다. 다음 mutation은 금지한다.

- `git add`, `commit`, `tag`, `fetch` into candidate refs, `checkout`, `switch`, `reset`, `merge`, `rebase`, `push`
- PR 생성·수정·merge, workflow dispatch·rerun·cancel, status/check 생성
- attestation subject/signature 작성·수정, trust/GPG keyring 변경
- tracked 또는 untracked repository file 생성·수정·삭제

검증은 live GitHub API와 이미 존재하는 local immutable object/tag만 읽는다. global preflight의 `git push --dry-run`도 Implement에서만 실행하고 verification mode에서는 생략한다. mode 종료 후 worktree/index/ref/control-plane snapshot이 하나라도 달라지면 판정을 폐기하고 exit `6`이다.

## 10. 실행 증거와 resume

`Implement`는 `.artifacts/codex/<run-id>/`에 bounded raw JSONL, stderr, final JSON, session UUID, immutable run manifest/hash, attempt별 resume state와 post-run evidence를 둔다. run manifest는 mode, exact run ID, trust/tool/workflow policy hash, prompt/schema/validator hash, 최초 HEAD와 full binary-safe worktree/control-plane snapshot을 가진다.

resume는 명시적 exact run ID만 허용한다.

```powershell
$runnerHost = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
& $runnerHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1' -Mode Implement -ResumeRun '<run-id>'
```

runner는 exclusive run lock을 획득한 뒤 manifest/state의 case-sensitive exact property set, `run_id`, attempt/path, session UUID, tool/trust/workflow hashes와 전체 worktree snapshot을 비교한다. 호출 직전 두 번째 snapshot이 같아야 하며 lock은 Codex 종료와 post-run snapshot까지 유지한다. resumed `thread.started.thread_id`는 저장 UUID와 같아야 한다. mismatch 또는 TOCTOU가 있으면 session을 호출하지 않는다.

`VerifyCandidate`와 `VerifyAccepted`는 Codex session이 없으므로 resume하지 않는다. 재실행은 같은 `R`과 같은 external bundle bytes를 처음부터 다시 읽어 검증한다.

## 11. 사람 승인 경계

다음은 `Implement` 밖이며 자동화가 우회할 수 없다.

- protected `main` workflow 설치·변경과 trust policy 갱신
- 7개 technical owner subject 검토·서명
- OWN-ACC 수용 검토·서명
- OWN-QA artifact signature와 signed annotated tag 생성·push
- main merge, production deploy, DNS 전환, 유료 provider/GPU 활성화
- destructive replacement와 실제 개인정보·기관 수용 데이터 승인

권장 순서는 `Implement` exit `5`와 `CANDIDATE_PHASE: UNSIGNED_CANDIDATE / REVIEW PENDING` 확인 → 사람이 `S`/`R`/PR/CI 검토 → 외부 7개 technical 및 artifact signature 생성 → `VerifyCandidate` → 수용 데이터·OWN-ACC 승인 → 외부 signed tag 생성·push → `VerifyAccepted`다.

## 12. 검증 절차

패키지 정적 계약과 schema fixture를 실행한다.

```bash
bash repo-overlay/scripts/tests/test-invoke-ai-training-platform-v1.sh
bash repo-overlay/scripts/tests/test-codex-final-result-schema-ajv.sh
```

Windows에서는 parser, policy fixture와 mode preflight를 추가 확인한다.

```powershell
[void][scriptblock]::Create((Get-Content -Raw .\repo-overlay\scripts\invoke-ai-training-platform-v1.ps1))
[void][scriptblock]::Create((Get-Content -Raw .\repo-overlay\scripts\validate-codex-final-result.ps1))
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\repo-overlay\scripts\tests\test-runner-policy-fixtures.ps1 -RunnerPath .\repo-overlay\scripts\invoke-ai-training-platform-v1.ps1
$runnerHost = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
& $runnerHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1' -Mode Implement -DryRun
```

policy self-test는 production runner가 실제 호출하는 동일한 identity/tool/CI/evidence/resume/state/bounds 함수를 사용해야 한다. duplicate mock policy로 PASS를 만들 수 없다. 음성시험은 self-reference `R`, wrong first parent, allowlist 밖 `S..R`, ambient/tool tamper, extra/missing CI, wrong PR/workflow/actor/label, evidence set mismatch, stale/wrong commit, resume TOCTOU, unsafe Git TLS/credential config, oversized stdout/stderr/JSONL과 hard timeout을 실제로 거부해야 한다.

PowerShell 없는 환경의 정적 성공은 Windows acceptance를 대신하지 않는다. production 실행·수용 host는 OS-protected Windows PowerShell 5.1 하나로 고정하며, 그 host에서 protected path·ACL·conditional Authenticode, direct `gh.exe` credential helper, public-only `gpg.exe`, actual GitHub PR/workflow/job binding, external detached signature, pre-existing signed annotated tag 및 read-only ref snapshot을 검증해야 한다. PowerShell 7은 parser와 `PolicySelfTest`의 cross-platform parity에만 사용하며 production acceptance 증거로 인정하지 않는다.
