#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/antinote-bridge-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

mkdir -p "$tmp_root/module-cache"
swiftc -O \
    -framework Foundation \
    -framework AppKit \
    -framework CryptoKit \
    -lsqlite3 \
    -module-cache-path "$tmp_root/module-cache" \
    "$repo_root/dot_local/share/personal-concierge/antinote-bridge/main.swift" \
    -o "$tmp_root/antinote"

db="$tmp_root/antinote.sqlite"
sqlite3 "$db" <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE ZNOTE (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZDBINDEX INTEGER, ZISSLOTTED INTEGER, ZISTUTORIAL INTEGER, ZSLOTINDEX INTEGER, ZSOFTDELETED INTEGER, ZCREATED TIMESTAMP, ZDELETEDAT TIMESTAMP, ZLASTMODIFIED TIMESTAMP, ZCKCHANGETAG VARCHAR, ZCONTENT VARCHAR, ZID BLOB, ZSKIPPEDURLS BLOB, ZCKSYSTEMFIELDS BLOB, ZISARCHIVED INTEGER, ZSYNCSTATE INTEGER, ZISPRIVATE INTEGER, ZISLOCKED INTEGER);
CREATE TABLE ZCHECKLISTITEM (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZCHECKED INTEGER, ZINDEX INTEGER, ZISHIDDEN INTEGER, ZRESPONSIBILITYRANGELENGTH INTEGER, ZRESPONSIBILITYRANGELOCATION INTEGER, ZNOTE INTEGER, ZVERTICALPOSITION FLOAT, ZCONTENT VARCHAR, ZID BLOB);
CREATE TABLE ZANTILINK (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZCURRENTRANGELENGTH INTEGER, ZCURRENTRANGELOCATION INTEGER, ZNOTE INTEGER, ZFULLURL VARCHAR, ZSHORTENEDURL VARCHAR, ZID BLOB);
CREATE TABLE ZATTACHMENT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZFILESIZE INTEGER, ZSORTORDER INTEGER, ZNOTE INTEGER, ZCREATED TIMESTAMP, ZFILENAME VARCHAR, ZFILETYPE VARCHAR, ZFILEURL VARCHAR, ZLOCATIONTYPE VARCHAR, ZMIMETYPE VARCHAR, ZID BLOB);
INSERT INTO ZNOTE (Z_PK,Z_OPT,ZDBINDEX,ZISSLOTTED,ZSLOTINDEX,ZSOFTDELETED,ZCREATED,ZLASTMODIFIED,ZCONTENT,ZID,ZISARCHIVED,ZISPRIVATE,ZISLOCKED) VALUES (1,3,100,0,0,0,800000000,800000010,'secret body',X'00112233445566778899AABBCCDDEEFF',0,0,0);
INSERT INTO ZNOTE (Z_PK,Z_OPT,ZDBINDEX,ZISSLOTTED,ZSLOTINDEX,ZSOFTDELETED,ZCREATED,ZLASTMODIFIED,ZCONTENT,ZID,ZISARCHIVED,ZISPRIVATE,ZISLOCKED) VALUES (2,4,200,1,4,0,800000000,800000009,'slotted body',X'102132435465768798A9BACBDCEDFE0F',0,0,0);
INSERT INTO ZNOTE (Z_PK,Z_OPT,ZDBINDEX,ZISSLOTTED,ZSLOTINDEX,ZSOFTDELETED,ZCREATED,ZDELETEDAT,ZLASTMODIFIED,ZCONTENT,ZID,ZISARCHIVED,ZISPRIVATE,ZISLOCKED) VALUES (3,5,300,0,0,1,800000000,800000011,800000008,'void body',X'AABBCCDDEEFF00112233445566778899',0,0,0);
INSERT INTO ZCHECKLISTITEM (Z_PK,ZCHECKED,ZINDEX,ZISHIDDEN,ZNOTE,ZCONTENT,ZID) VALUES (1,0,0,0,1,'do thing',X'FFEEDDCCBBAA99887766554433221100');
INSERT INTO ZANTILINK (Z_PK,ZNOTE,ZFULLURL,ZSHORTENEDURL,ZID) VALUES (1,1,'https://example.test/item','https://example.test',X'102132435465768798A9BACBDCEDFE0F');
SQL

"$tmp_root/antinote" --version | jq -e '.ok and .version == "0.1.0" and .helperVersion == "0.1.0"' >/dev/null
"$tmp_root/antinote" version | jq -e '.ok and .version == "0.1.0"' >/dev/null

id="00112233-4455-6677-8899-aabbccddeeff"
list_json="$tmp_root/list.json"
"$tmp_root/antinote" list --db "$db" --json >"$list_json"
jq -e '.ok and .count == 2 and .notes[0].id == "00112233-4455-6677-8899-aabbccddeeff" and .notes[0].revision == 3 and .notes[0].stackIndex == 100 and (.notes[0] | has("content") | not) and (.notes[0] | has("slotIndex") | not) and (.notes[0].checklists[0] | has("content") | not) and ([.notes[] | select(.slotted)] | length == 1) and ([.notes[] | select(.slotted) | has("slotIndex")] | all) and ([.notes[] | select(.slotted) | .revision == 4 and .stackIndex == 200] | all)' "$list_json" >/dev/null

show_json="$tmp_root/show.json"
"$tmp_root/antinote" show "$id" --db "$db" --json >"$show_json"
jq -e '.ok and .note.content == "secret body" and .note.checklists[0].content == "do thing" and .note.links[0].url == "https://example.test/item"' "$show_json" >/dev/null

"$tmp_root/antinote" search secret --db "$db" --json | jq -e '.ok and .count == 1' >/dev/null
"$tmp_root/antinote" changes --since 2025-01-01T00:00:00Z --include-settling --db "$db" --json | jq -e '.ok and .count == 3 and (.notes[0] | has("content") | not) and ([.notes[] | select(.state == "void")] | length == 1)' >/dev/null
"$tmp_root/antinote" changes --since 2025-01-01T00:00:00Z --include-settling --exclude-void --db "$db" --json | jq -e '.ok and .count == 2 and ([.notes[] | select(.state == "void")] | length == 0)' >/dev/null
"$tmp_root/antinote" verify "$id" --db "$db" --json | jq -e '.ok and .contentMatches and .metadataMatches' >/dev/null
"$tmp_root/antinote" create-url --content 'hello & goodbye' --db "$db" --json | jq -e '.ok and (.url | startswith("antinote://x-callback-url/createNote?content="))' >/dev/null

backup="$tmp_root/backup.sqlite"
backup_result="$tmp_root/backup-result.json"
set +e
"$tmp_root/antinote" backup --output "$backup" --db "$db" --json >"$backup_result"
backup_status=$?
set -e
jq . "$backup_result"
[[ "$backup_status" -eq 0 ]]
jq -e '.ok and .permissions == "0600" and .quickCheck == "ok" and .integrityCheck == "ok" and (.path | endswith("/backup.sqlite"))' "$backup_result" >/dev/null
[[ "$(sqlite3 "$backup" 'PRAGMA integrity_check')" == "ok" ]]
[[ "$(stat -f '%Lp' "$backup")" == "600" ]]

symlink_target="$tmp_root/symlink-target.sqlite"
touch "$symlink_target"
symlink_destination="$tmp_root/symlink.sqlite"
ln -s "$symlink_target" "$symlink_destination"
symlink_result="$tmp_root/symlink-result.json"
set +e
"$tmp_root/antinote" backup --output "$symlink_destination" --db "$db" --json >"$symlink_result"
symlink_status=$?
set -e
[[ "$symlink_status" -ne 0 ]]
jq -e '.ok == false and (.error | contains("symlink"))' "$symlink_result" >/dev/null

bad_db="$tmp_root/bad.sqlite"
sqlite3 "$bad_db" 'CREATE TABLE ZNOTE (ZID BLOB);'
"$tmp_root/antinote" doctor --db "$bad_db" --json | jq -e '.ok == false and .schemaGuard.ok == false and (.schemaGuard.missingColumns | length) > 0' >/dev/null
bad_list="$tmp_root/bad-list.json"
set +e
"$tmp_root/antinote" list --db "$bad_db" --json >"$bad_list"
bad_status=$?
set -e
[[ "$bad_status" -ne 0 ]]
jq -e '.ok == false and (.error | contains("schema guard"))' "$bad_list" >/dev/null

bad_type_db="$tmp_root/bad-type.sqlite"
sqlite3 "$bad_type_db" <<'SQL'
CREATE TABLE ZNOTE (Z_PK INTEGER PRIMARY KEY, Z_OPT INTEGER, ZDBINDEX INTEGER, ZISSLOTTED INTEGER, ZSLOTINDEX INTEGER, ZSOFTDELETED INTEGER, ZCREATED TIMESTAMP, ZDELETEDAT TIMESTAMP, ZLASTMODIFIED TIMESTAMP, ZCONTENT VARCHAR, ZID TEXT, ZISARCHIVED INTEGER, ZISPRIVATE INTEGER, ZISLOCKED INTEGER);
CREATE TABLE ZCHECKLISTITEM (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZCHECKED INTEGER, ZINDEX INTEGER, ZISHIDDEN INTEGER, ZNOTE INTEGER, ZCONTENT VARCHAR);
CREATE TABLE ZANTILINK (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZNOTE INTEGER, ZFULLURL VARCHAR, ZSHORTENEDURL VARCHAR);
CREATE TABLE ZATTACHMENT (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZNOTE INTEGER, ZFILESIZE INTEGER, ZSORTORDER INTEGER, ZFILENAME VARCHAR, ZFILETYPE VARCHAR, ZFILEURL VARCHAR, ZMIMETYPE VARCHAR);
INSERT INTO ZNOTE (Z_PK,Z_OPT,ZDBINDEX,ZISSLOTTED,ZSLOTINDEX,ZSOFTDELETED,ZCREATED,ZLASTMODIFIED,ZCONTENT,ZID,ZISARCHIVED,ZISPRIVATE,ZISLOCKED) VALUES (1,1,1,0,0,0,800000000,800000000,'bad type','not-a-blob',0,0,0);
SQL
"$tmp_root/antinote" doctor --db "$bad_type_db" --json | jq -e '.ok == false and (.schemaGuard.invalidTypes | map(select(.table == "ZNOTE" and .column == "ZID")) | length == 1)' >/dev/null

bad_identity_db="$tmp_root/bad-identity.sqlite"
cp "$db" "$bad_identity_db"
sqlite3 "$bad_identity_db" "UPDATE ZNOTE SET ZID = X'01' WHERE Z_PK = 1;"
"$tmp_root/antinote" doctor --db "$bad_identity_db" --json | jq -e '.ok == false and (.schemaGuard.invalidIdentities | map(select(.table == "ZNOTE")) | length == 1)' >/dev/null

echo "antinote bridge tests passed"
