"""Every Synapse SQL file must parse cleanly with the T-SQL grammar (sqlfluff)."""

from pathlib import Path

import pytest
import sqlfluff
from sqlfluff.api.simple import APIParsingError

SQL_DIR = Path(__file__).resolve().parents[1] / "synapse" / "sql"
FILES = sorted(SQL_DIR.rglob("*.sql"))


def test_sql_files_found():
    assert len(FILES) >= 10


@pytest.mark.parametrize("path", FILES, ids=lambda p: str(p.relative_to(SQL_DIR)))
def test_sql_parses_as_tsql(path):
    sqlfluff.parse(path.read_text(encoding="utf-8"), dialect="tsql")  # raises on any unparsable segment


def test_parser_rejects_broken_sql():
    with pytest.raises(APIParsingError):
        sqlfluff.parse("CREATE TABLE x (a INT,, b INT);", dialect="tsql")
