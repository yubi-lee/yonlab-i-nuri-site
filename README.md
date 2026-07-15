# YOnLab AI 연수 플랫폼 설계·실행 패키지 v1.1

이 패키지는 `D:\Views\yonlab-inuri-site`의 `feat/ai-training-platform-v1` 브랜치를 기준으로, 보육교사 AI 역량진단·페르소나·맞춤 연수 추천·Document AI·HWP 구조 보존형 RAG·AI Gateway를 구현하기 위한 **타이트한 설계 기준선과 안전 실행기**를 제공합니다.

패키지 자체가 완성 애플리케이션은 아닙니다. 대상 Git 저장소에 검증된 설계 overlay를 설치하고 사람이 변경 내용을 commit한 뒤, 한 명령으로 Codex 구현·시험·문서화·feature branch push·draft PR 생성을 진행하도록 구성했습니다.

## 패키지 구성

- `yonlab-ai-training-platform-design/`: 요구사항, 화면, 아키텍처, AI, 데이터, 보안, 시험, 운영, 시각 체계 및 최종 산출물 계약
- `AI-Gateway-UniClaudeProxy-Reuse-Design.md`: UniClaudeProxy 분석과 제한적 재사용 설계
- `generate-overlay-manifest.py`: 재귀 source→destination 정책의 단일 생성·검증 구현
- `overlay-manifest.json`: 97개 설치 파일의 canonical source/destination, SHA-256, byte length, mode 계약
- `start-ai-training-platform-v1.ps1`: overlay 점검·설치·실행 bootstrap
- `repo-overlay/`: 대상 저장소에 설치되는 Codex runner와 strict 결과 validator

## 고정 대상

| 항목 | 값 |
|---|---|
| 작업 경로 | `D:\Views\yonlab-inuri-site` |
| Git remote | `https://github.com/yubi-lee/yonlab-i-nuri-site.git` |
| 작업 branch | `feat/ai-training-platform-v1` |
| 기준선 | `YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1` |

경로·remote·branch 중 하나라도 다르거나 worktree가 dirty이면 실행기는 자동 수정하지 않고 중단합니다.

## 배포 신뢰 경계

패키지 내부 verifier는 파일 간 정합성과 변조 여부를 검사하지만, 패키지 발행자의 신원을 스스로 증명하지는 못합니다. 압축을 풀기 전에 반드시 배포 채널에 별도로 게시된 ZIP SHA-256과 다운로드 파일의 SHA-256을 비교해야 합니다. 값이 다르면 어떤 패키지 스크립트도 실행하지 않습니다. 이 외부 checksum 확인이 최초 신뢰점이며, 압축 해제 후에는 workspace 밖의 보호된 `release-trust.v2`가 도구·키·workflow 신뢰를 이어받습니다. 최초 hash는 profile 함수·alias를 거치지 않도록 아래의 절대 OS `certutil.exe`로 계산하고 사람이 64자리 값을 대조합니다.

```powershell
& 'C:\Windows\System32\certutil.exe' -hashfile '.\YOnLab-AI-Training-Platform-Design-v1.1.zip' SHA256
# 출력된 64자리 값을 배포 메시지의 SHA-256과 문자 단위로 비교한다.
# 다르면 압축을 풀거나 패키지 안의 명령을 실행하지 않는다.
```

## 시작 전 준비

> 현재 release trust 실값, owner 공개키/fingerprint, GitHub workflow ID·hash, hardened ProgramData ACL과 외부 서명은 패키지에 포함되지 않는 관리자 선행조건입니다. 이 값들이 승인·provision되기 전 상태는 `EXTERNAL PREREQUISITES PENDING / NOT_READY`이며, placeholder template으로는 구현을 시작할 수 없습니다.

Windows PowerShell에서 다음을 확인합니다.

```powershell
git --version
python --version
docker version
docker compose version
codex --version
codex login status
gh --version
gh auth status
gpg --version
```

대상 저장소는 위 표의 branch에 있고 clean 상태여야 합니다.

```powershell
Set-Location D:\Views\yonlab-inuri-site
git status --short
git branch --show-current
git remote get-url origin
```

성공 candidate 검증에는 workspace 밖의 보호된 `C:\ProgramData\YOnLab\release-trust.json`이 필수입니다. [`release-trust.example.json`](yonlab-ai-training-platform-design/release-trust.example.json)은 placeholder가 남아 있어 의도적으로 실행 불가능한 non-secret template입니다. exact fingerprint 입력, GPG 공개키 import, owner/SYSTEM/Administrators 전용 ACL 절차는 [한 명령 실행 설계 4절](yonlab-ai-training-platform-design/13-one-command-execution.md#4-fail-closed-preflight)을 따릅니다.

bootstrap과 runner가 실행하는 도구는 Windows/System32, Program Files 또는 hardened `C:\ProgramData\YOnLab\bin` 아래의 exact absolute path만 허용합니다. executable부터 volume root까지 모든 구성요소의 reparse 여부, ACL owner, write/modify/delete/control ACE를 검사하므로 user-writable LocalAppData 경로는 신뢰 root로 쓰지 않습니다.

### Overlay 파일 소유권

`yonlab-ai-training-platform-design/` 아래 regular file 90개 중 package 자체에서만 사용하는 `verify-design-package.sh`, `verify-design-package.ps1`, `test-verify-design-package.sh` 3개를 제외한 87개를 동일한 하위 경로로 설치합니다. 여기에 AI Gateway 분석 문서와 manifest generator 2개, `repo-overlay/`의 runner·validator·회귀시험 8개를 더해 총 97개를 설치합니다. `reference/private/`, `.artifacts/`, symbolic link/reparse point, `__pycache__`, `.pyc/.pyo`, 누락·추가 entry, 목적지 변경, byte length·mode·SHA drift는 모두 실패합니다.

목록을 손으로 편집하지 않습니다. 설계 산출물을 추가·삭제·변경한 뒤 다음 명령으로만 재생성하고 즉시 canonical check를 수행합니다.

```powershell
$env:PYTHONDONTWRITEBYTECODE = "1"
python .\generate-overlay-manifest.py --root . --write
python .\generate-overlay-manifest.py --root . --check
```

## 1. 패키지 검증

압축을 푼 패키지 root에서 PowerShell 검증기를 실행합니다.

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\yonlab-ai-training-platform-design\verify-design-package.ps1
```

Git Bash 또는 WSL에서는 동등한 Bash 검증기를 사용할 수 있습니다.

```bash
bash yonlab-ai-training-platform-design/verify-design-package.sh
```

두 검증기는 같은 `OVERLAY_POLICY_V2_RECURSIVE_EXACT` 정책 생성기를 호출하고, completeness/source-traceability/machine-contract checker를 모두 실행합니다. `RESULT: PASS`가 아니면 overlay를 설치하지 않습니다. 검증 실행 자체는 bytecode cache를 만들지 않습니다.

## 2. Overlay 점검과 설치

먼저 쓰기 없는 dry run을 실행합니다.

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\start-ai-training-platform-v1.ps1 -InstallOverlay -DryRun
```

예정 파일을 검토한 뒤 설치합니다.

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\start-ai-training-platform-v1.ps1 -InstallOverlay
```

설치기는 manifest에 등록된 파일만 복사하고, 기존 대상 파일은 `.artifacts/codex/overlay-backups/`에 백업합니다. 설치가 끝나면 대상 저장소의 diff를 검토하고 사람이 commit·push합니다. 이 경계는 clean-worktree 재현성을 위한 의도적인 안전 절차입니다.

첫 대상 파일을 바꾸기 전에 `transaction.json`과 모든 기존 파일의 durable backup을 기록합니다. 전원 종료나 강제 종료로 `PREPARED`/`APPLYING` transaction이 남으면 다음 실행은 `OVERLAY-RECOVERY`로 중단하며, 해당 journal과 backup을 이용해 원상 복구하기 전에는 새 설치를 시작하지 않습니다. source의 `Zone.Identifier`는 복사하지 않고, 그 밖의 NTFS alternate stream은 거부합니다.

```powershell
Set-Location D:\Views\yonlab-inuri-site
git diff --check
git status --short
git add docs/planning scripts .gitignore
git commit -m "docs: install AI training platform v1.1 execution baseline"
git push origin feat/ai-training-platform-v1
```

## 3. 한 명령 구현 실행

overlay commit 후 대상 저장소에서 다음 한 줄을 실행합니다.

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1'
```

이 한 줄이 preflight, guarded Codex 구현, 재개 가능한 evidence 생성, 시험, 문서화, feature branch push와 draft PR 준비를 담당합니다. Overlay 설치와 사람의 기준선 commit은 공급망 경계이므로 이 명령에 합치지 않습니다.

또는 압축 패키지 root에서 bootstrap을 사용할 수 있습니다.

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\start-ai-training-platform-v1.ps1
```

실행기는 Codex를 `workspace-write` sandbox와 `on-request` 승인 정책으로 시작하고 attempt별 JSONL/최종 결과, binary-safe resume snapshot, 구현 commit `S`, 직계 release snapshot `R`, Git·PR·exact CI·canonical evidence index·최종 문서의 독립 검증 결과를 `.artifacts/codex/<run-id>/`에 남깁니다. Codex 변경 뒤 작업 트리 validator/verifier를 host에서 실행하지 않고 실행 전에 고정한 raw bytes와 runner 내부 검사를 사용합니다. `--yolo`, sandbox 우회, `--last` 세션 재개는 허용하지 않습니다.

명령·JSONL·`--output-schema` 동작은 [OpenAI Codex CLI reference](https://developers.openai.com/codex/cli/reference/)와 [non-interactive mode](https://developers.openai.com/codex/noninteractive/)를 기준으로 고정했습니다. 모델에 전달하는 schema는 Structured Outputs 지원 subset만 사용하고, 상태 전이·KPI·경로 같은 더 엄격한 의미 규칙은 별도 offline validator가 검사합니다.

중단 시 화면에 출력된 exact `-ResumeRun '<run-id>'` 명령만 사용합니다. 임의로 `codex exec resume --last`를 실행하지 않습니다.

## 완료 판정

- `Implement`: Codex가 선언할 수 있는 `release_state`는 항상 `NOT_READY`입니다. 구현 가능한 모든 gate가 통과하면 별도 `candidate_phase=UNSIGNED_CANDIDATE / REVIEW PENDING`과 exit `5`로 멈춥니다.
- `VerifyCandidate`: 외부 보호 저장소의 7개 technical 승인, artifact 서명, exact PR·CI를 읽기 전용으로 검증한 경우에만 `CODE_COMPLETE / ACCEPTANCE DATA PENDING`을 판정합니다.
- `VerifyAccepted`: 위 검증에 OWN-ACC와 이미 존재하는 signed annotated tag까지 통과한 경우에만 `ACCEPTED`를 판정합니다.

`CODE_COMPLETE / ACCEPTANCE DATA PENDING`은 완료 승인이 아니며 `ACCEPTED`로 자동 승격되지 않습니다. `main` merge, tag 생성·push, 운영 배포, 유료 provider 활성화, 파괴적 교체는 runner가 대신하지 않는 사람 승인 범위입니다. 네 CI check는 `R`과 exact PR에 각각 하나씩 `COMPLETED/SUCCESS`여야 하며 candidate가 새로 만든 workflow는 신뢰하지 않습니다.

## 상세 문서

설계 문서의 읽기 순서와 규범 우선순위는 [`yonlab-ai-training-platform-design/README.md`](yonlab-ai-training-platform-design/README.md)를 따릅니다. 실행·복구 계약은 `13-one-command-execution.md`, 최종 설계·운영·시험·매뉴얼 산출물 계약은 `14-final-document-deliverables.md`와 `final-document-inventory.json`에 있습니다.

## 플랫폼 확인 범위

패키지 검증은 Bash와 PowerShell 7에서 수행합니다. 실제 목표 환경의 Windows PowerShell 5.1, `.cmd` shim, Docker Desktop, GitHub 인증은 대상 PC에서 overlay 설치 전 dry run과 runner `-DryRun`으로 한 번 더 확인해야 합니다.
