#!/bin/bash
# End-to-end check for kissmark-mcp memory tools (ADR 0028).
set -euo pipefail

cd "$(dirname "$0")"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/kissmark-mcp"
[ -x "$BIN" ] || { echo "FAIL: binary not built"; exit 1; }

STORE="$(mktemp -d)"
trap 'rm -rf "$STORE" "$DOCS" "$STORE_EMPTY" "$STORE_V1"' EXIT
DOCS="$(mktemp -d)"
STORE_EMPTY="$(mktemp -d)"
mkdir -p "$DOCS/p1" "$DOCS/p2"
printf '# 배포 노트\n배포 계획 문서입니다.\n' > "$DOCS/p1/배포노트.md"
printf '# Deploy Plan\nThis is the deploy plan for release 42.\n' > "$DOCS/p2/deploy-plan.md"
# Paths are NFC-normalized on both sides (contract), so the typed Hangul path matches.
KMD="$DOCS/p1/배포노트.md"

# Fixture memory.sqlite with the contract schema (project P1 = Korean doc, P2 = deploy plan;
# one agent open, one user open; P2 is newer).
/usr/bin/sqlite3 "$STORE/memory.sqlite" >/dev/null <<SQL
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS documents (
  path TEXT PRIMARY KEY, title TEXT NOT NULL,
  first_opened_at REAL NOT NULL, last_opened_at REAL NOT NULL,
  open_count INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS opens (
  id INTEGER PRIMARY KEY, path TEXT NOT NULL REFERENCES documents(path),
  opened_at REAL NOT NULL, opener TEXT NOT NULL CHECK (opener IN ('agent','user')),
  project TEXT, host TEXT, agent TEXT, session TEXT);
CREATE INDEX IF NOT EXISTS opens_path_time ON opens(path, opened_at DESC);
CREATE VIRTUAL TABLE IF NOT EXISTS document_text USING fts5(path UNINDEXED, title, body, tokenize = 'trigram');
PRAGMA user_version = 1;
INSERT INTO documents VALUES ('$KMD', '배포노트', 1700000000, 1700000000, 1);
INSERT INTO documents VALUES ('$DOCS/p2/deploy-plan.md', 'deploy-plan', 1700001000, 1700001000, 1);
INSERT INTO opens (path, opened_at, opener, project, host, agent) VALUES
  ('$KMD', 1700000000, 'agent', '$DOCS/p1', 'claude-code', 'test-agent'),
  ('$DOCS/p2/deploy-plan.md', 1700001000, 'user', '$DOCS/p2', NULL, NULL);
INSERT INTO document_text VALUES
  ('$KMD', '배포노트', '배포 계획 문서입니다.'),
  ('$DOCS/p2/deploy-plan.md', 'deploy-plan', 'This is the deploy plan for release 42.');
CREATE TABLE IF NOT EXISTS review_points (
  id INTEGER PRIMARY KEY,
  path TEXT NOT NULL REFERENCES documents(path),
  source TEXT NOT NULL CHECK (source IN ('agent', 'rule')),
  kind TEXT NOT NULL CHECK (kind IN ('agent', 'decision', 'warning', 'failure', 'next', 'task', 'changed')),
  heading TEXT, quote TEXT NOT NULL, note TEXT,
  created_at REAL NOT NULL, checked_at REAL, comment TEXT,
  host TEXT, agent TEXT, session TEXT);
CREATE INDEX IF NOT EXISTS review_points_path ON review_points(path, checked_at);
CREATE TABLE IF NOT EXISTS review_completions (
  path TEXT PRIMARY KEY REFERENCES documents(path),
  completed_at REAL NOT NULL, snapshot TEXT NOT NULL);
PRAGMA user_version = 2;
INSERT INTO review_points (path, source, kind, heading, quote, note, created_at, checked_at, comment, host, agent, session) VALUES
  ('$DOCS/p2/deploy-plan.md', 'agent', 'agent', NULL, 'First issue found.', 'check this', 1700000001, NULL, NULL, 'check-sh', 'check-agent', 's1'),
  ('$DOCS/p2/deploy-plan.md', 'agent', 'agent', NULL, 'Second issue found.', NULL, 1700000002, 1700000099, 'looks fine', 'check-sh', 'check-agent', 's1'),
  ('$DOCS/p2/deploy-plan.md', 'rule', 'warning', 'Warnings', 'Release 42 is risky.', NULL, 1700000003, NULL, NULL, NULL, NULL, NULL);
INSERT INTO review_completions VALUES ('$KMD', 1700000050, 'old snapshot');
SQL

# Round-1-only fixture: v1 schema, no review tables.
STORE_V1="$(mktemp -d)"
/usr/bin/sqlite3 "$STORE_V1/memory.sqlite" >/dev/null <<SQL
PRAGMA journal_mode = WAL;
CREATE TABLE documents (
  path TEXT PRIMARY KEY, title TEXT NOT NULL,
  first_opened_at REAL NOT NULL, last_opened_at REAL NOT NULL,
  open_count INTEGER NOT NULL DEFAULT 0);
CREATE TABLE opens (
  id INTEGER PRIMARY KEY, path TEXT NOT NULL REFERENCES documents(path),
  opened_at REAL NOT NULL, opener TEXT NOT NULL CHECK (opener IN ('agent','user')),
  project TEXT, host TEXT, agent TEXT, session TEXT);
INSERT INTO documents VALUES ('$DOCS/p2/deploy-plan.md', 'deploy-plan', 1700001000, 1700001000, 1);
PRAGMA user_version = 1;
SQL

fail=0
check() { # check <name> <condition-result: 0 ok>
  if [ "$2" -eq 0 ]; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi
}

# Drive the server with one stdio session; replies land in $OUT.
call() { # call <requests-file> [extra env]
  OUT="$(env KISSMARK_STORE_DIR="$STORE" KISSMARK_BUNDLE_ID="${BUNDLE:-com.singandmong.kissmark}" \
    "$BIN" < "$1")"
}

REQ="$(mktemp)"
trap 'rm -rf "$STORE" "$DOCS" "$STORE_EMPTY" "$STORE_V1" "$REQ"' EXIT
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"check-sh"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"recent_documents","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"recent_documents","arguments":{"project":"'"$DOCS"'/p1"}}}' \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"recent_documents","arguments":{"limit":1}}}' \
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"배포"}}}' \
  '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"DEPLOY"}}}' \
  '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":""}}}' \
  > "$REQ"
call "$REQ"

# tools/list names 5 tools
LIST_LINE="$(printf '%s\n' "$OUT" | grep '"id":2')"
for tool in open_document recent_documents search_documents add_review_points review_status; do
  printf '%s' "$LIST_LINE" | grep -q "\"name\":\"$tool\""; check "tools/list contains $tool" $?
done
COUNT="$(printf '%s' "$LIST_LINE" | tr ',' '\n' | grep -c '"name":"' || true)"
[ "$COUNT" -eq 5 ]; check "tools/list lists exactly 5 tools" $?

# recent_documents: newest first (deploy-plan before 배포노트)
RECENT="$(printf '%s\n' "$OUT" | grep '"id":3')"
# The tool text is an escaped JSON string; strip backslash-escapes before grepping.
CLEAN="$(printf '%s' "$RECENT" | sed 's/\\"/"/g')"
FIRST_IS_P2=$([ "$(printf '%s' "$CLEAN" | grep -o '"path":"[^"]*"' | head -1)" = "\"path\":\"$DOCS/p2/deploy-plan.md\"" ] && echo y || echo n)
check "recent_documents orders newest first" $([ "$FIRST_IS_P2" = y ] && echo 0 || echo 1)

# project filter: only p1
FILTERED="$(printf '%s\n' "$OUT" | grep '"id":4')"
check "recent_documents honours project filter" $(printf '%s' "$FILTERED" | grep -q '배포노트' && ! printf '%s' "$FILTERED" | grep -q 'deploy-plan' && echo 0 || echo 1)

# limit 1: single entry
LIMITED="$(printf '%s\n' "$OUT" | grep '"id":5')"
LIMITED_CLEAN="$(printf '%s' "$LIMITED" | sed 's/\\"/"/g')"
check "recent_documents honours limit" $([ "$(printf '%s' "$LIMITED_CLEAN" | grep -o '"path":"' | wc -l | tr -d ' ')" = 1 ] && echo 0 || echo 1)

# search 배포 (Korean, 2 syllables)
KOR="$(printf '%s\n' "$OUT" | grep '"id":6')"
check "search_documents finds 배포" $(printf '%s' "$KOR" | grep -q '배포노트' && printf '%s' "$KOR" | grep -q 'snippet' && echo 0 || echo 1)

# search DEPLOY (ASCII case-insensitive)
ASCII="$(printf '%s\n' "$OUT" | grep '"id":7')"
check "search_documents finds DEPLOY case-insensitively" $(printf '%s' "$ASCII" | grep -q 'deploy-plan' && echo 0 || echo 1)

# empty query is an error
EMPTY="$(printf '%s\n' "$OUT" | grep '"id":8')"
check "search_documents empty query is an error" $(printf '%s' "$EMPTY" | grep -q '"isError":true' && echo 0 || echo 1)

# empty store dir -> {"documents": []}
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"recent_documents","arguments":{}}}' > "$REQ"
OUT="$(KISSMARK_STORE_DIR="$STORE_EMPTY" "$BIN" < "$REQ")"
EMPTY_OUT="$(printf '%s\n' "$OUT" | grep '"id":2' | sed 's/\\"/"/g')"
check "missing memory.sqlite returns empty list" $(printf '%s' "$EMPTY_OUT" | grep -q '"documents":\[\]' && echo 0 || echo 1)

# a checkpointed WAL store without -wal/-shm (restored or copied) is still readable
/usr/bin/sqlite3 "$STORE/memory.sqlite" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null
rm -f "$STORE/memory.sqlite-wal" "$STORE/memory.sqlite-shm"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"배포"}}}' > "$REQ"
OUT="$(KISSMARK_STORE_DIR="$STORE" "$BIN" < "$REQ")"
check "store without -shm stays readable" $(printf '%s\n' "$OUT" | grep '"id":2' | grep -q '배포노트' && echo 0 || echo 1)

# open_document with missing bundle id: isError, queue cleaned up
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"check-sh"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"open_document","arguments":{"path":"'"$DOCS"'/p1/배포노트.md","project":"'"$DOCS"'/p1","agent":"check-agent","session":"s1"}}}' > "$REQ"
OUT="$(KISSMARK_STORE_DIR="$STORE" KISSMARK_BUNDLE_ID=com.example.missing "$BIN" < "$REQ")"
check "open_document missing bundle is error" $(printf '%s\n' "$OUT" | grep '"id":2' | grep -q '"isError":true' && echo 0 || echo 1)
QCOUNT="$(ls "$STORE/queue" 2>/dev/null | grep -c '\.json$' || true)"
check "failed open_document leaves no queue file" $([ "$QCOUNT" = 0 ] && echo 0 || echo 1)

# --- Round 2: review points ---

# review_status on the v2 fixture: 3 points in created_at order, checked/comment/agent present
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"check-sh"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"review_status","arguments":{"path":"'"$DOCS"'/p2/deploy-plan.md"}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"review_status","arguments":{"path":"'"$DOCS"'/p1/배포노트.md"}}}' > "$REQ"
OUT="$(KISSMARK_STORE_DIR="$STORE" "$BIN" < "$REQ")"
STATUS="$(printf '%s\n' "$OUT" | grep '"id":2' | sed 's/\\"/"/g')"
check "review_status returns 3 points" $([ "$(printf '%s' "$STATUS" | grep -o '"quote":"' | wc -l | tr -d ' ')" = 3 ] && echo 0 || echo 1)
check "review_status orders points by created_at" $([ "$(printf '%s' "$STATUS" | grep -o '"quote":"[^"]*"' | head -1)" = '"quote":"First issue found."' ] && echo 0 || echo 1)
check "review_status reports checked_at and comment" $(printf '%s' "$STATUS" | grep -q '"checked_at":"2' && printf '%s' "$STATUS" | grep -q '"comment":"looks fine"' && echo 0 || echo 1)
check "review_status reports agent" $(printf '%s' "$STATUS" | grep -q '"agent":"check-agent"' && echo 0 || echo 1)
check "review_status reports source" $(printf '%s' "$STATUS" | grep -q '"source":"rule"' && printf '%s' "$STATUS" | grep -q '"source":"agent"' && echo 0 || echo 1)
COMPLETED="$(printf '%s\n' "$OUT" | grep '"id":3' | sed 's/\\"/"/g')"
check "review_status reports completed_at" $(printf '%s' "$COMPLETED" | grep -q '"completed_at":"2' && echo 0 || echo 1)

# review_status on a round-1-only store and on an empty store: no points, completed_at null
for CASE in "v1:$STORE_V1" "empty:$STORE_EMPTY"; do
  NAME="${CASE%%:*}"; DIR="${CASE#*:}"
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"review_status","arguments":{"path":"'"$DOCS"'/p2/deploy-plan.md"}}}' > "$REQ"
  OUT="$(KISSMARK_STORE_DIR="$DIR" "$BIN" < "$REQ")"
  NOPOINTS="$(printf '%s\n' "$OUT" | grep '"id":2' | sed 's/\\"/"/g')"
  check "review_status on $NAME store returns no points" $(printf '%s' "$NOPOINTS" | grep -q '"points":\[\]' && printf '%s' "$NOPOINTS" | grep -q '"completed_at":null' && echo 0 || echo 1)
done

# invalid points are tool errors (open_document: empty quote; add_review_points: 21 points)
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"open_document","arguments":{"path":"'"$DOCS"'/p2/deploy-plan.md","points":[{"quote":""}]}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"add_review_points","arguments":{"path":"'"$DOCS"'/p2/deploy-plan.md","points":['"$(for i in $(seq 21); do printf '{"quote":"p%d"}\n' "$i"; done | paste -sd, -)"']}}}' > "$REQ"
OUT="$(KISSMARK_BUNDLE_ID=com.example.missing KISSMARK_STORE_DIR="$STORE" "$BIN" < "$REQ")"
check "open_document empty quote is an error" $(printf '%s\n' "$OUT" | grep '"id":2' | grep -q '"isError":true' && echo 0 || echo 1)
check "add_review_points 21 points is an error" $(printf '%s\n' "$OUT" | grep '"id":3' | grep -q '"isError":true' && echo 0 || echo 1)

# add_review_points with a missing bundle id: isError, no queue file left behind
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"check-sh"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"add_review_points","arguments":{"path":"'"$DOCS"'/p2/deploy-plan.md","agent":"check-agent","points":[{"quote":"First issue found.","note":"check"}]}}}' > "$REQ"
OUT="$(KISSMARK_STORE_DIR="$STORE" KISSMARK_BUNDLE_ID=com.example.missing "$BIN" < "$REQ")"
check "add_review_points missing bundle is error" $(printf '%s\n' "$OUT" | grep '"id":2' | grep -q '"isError":true' && echo 0 || echo 1)
QCOUNT="$(ls "$STORE/queue" 2>/dev/null | grep -c '\.json$' || true)"
check "failed add_review_points leaves no queue file" $([ "$QCOUNT" = 0 ] && echo 0 || echo 1)

exit $fail
