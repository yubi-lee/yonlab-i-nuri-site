import os
import sqlite3
import subprocess
import sys
from pathlib import Path


def test_alembic_upgrade_creates_complete_schema(tmp_path: Path):
    database = tmp_path / "migration.db"
    env = os.environ.copy()
    env["DATABASE_URL"] = f"sqlite:///{database.as_posix()}"
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "-c", "alembic.ini", "upgrade", "head"],
        cwd=Path(__file__).parents[1],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    with sqlite3.connect(database) as connection:
        tables = {row[0] for row in connection.execute("select name from sqlite_master where type='table'")}
    assert {"users", "refresh_sessions", "password_reset_tokens", "resources", "resource_attachments", "audit_logs"} <= tables
