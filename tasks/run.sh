#!/usr/bin/env bash
# Usage: tasks/run.sh T01   (runs one task end to end; costs no Claude tokens)
# Reads tasks/<ID>.md header (before the --- line): title, runner, finding, files, max_diff, tests_min.
set -uo pipefail
cd "$(dirname "$0")/.."
T=$1; F=tasks/$T.md
h() { sed -n "1,/^---$/p" "$F" | sed -n "s/^$1: //p"; }
title=$(h title); runner=$(h runner); finding=$(h finding); files=$(h files); max=$(h max_diff); tmin=$(h tests_min)
[ -z "$(git status --porcelain --untracked-files=no -- . ':!tasks/LOG.md')" ] || { echo "STOP: tracked files are dirty, commit or stash first"; exit 2; }
base=$(git rev-parse HEAD); t0=$(date +%s)
prompt="Do tasks/$T.md exactly. Edit ONLY these files: $files. Do not edit pubspec.yaml, lib/phase.dart or anything else. Keep the diff small."
case $runner in
  pi)    PI_VERIFY="flutter analyze && flutter test" PI_MAX_ITERS=2 PI_TIMEOUT=900 \
           ~/.claude/skills/pi-delegate/scripts/pi-run.sh "$prompt Do not try to run commands; a wrapper runs analyze and tests after you finish." $F ${files//,/ } >/tmp/$T.log 2>&1 ;;
  codex) codex exec -s workspace-write -C . "$prompt Then run 'flutter analyze' and 'flutter test' and fix any failure." >/tmp/$T.log 2>&1 ;;
  *) echo "bad runner"; exit 2 ;;
esac
status=OK; why=""
# Gate 1: only allowed files changed
allowed=",$files,"
for f in $( (git diff --name-only "$base"; git ls-files --others --exclude-standard) | grep -vE '^(\.pi-runs/|audit/|2026-|tasks/LOG\.md$)'); do
  case "$allowed" in *",$f,"*) ;; *) status=FAIL; why="touched $f";; esac
done
# Gate 2: diff size
lines=$(git diff --numstat "$base" | awk '{s+=$1+$2} END{print s+0}')
[ "$lines" -le "${max:-80}" ] || { status=FAIL; why="$why diff $lines>$max"; }
# Gate 3: analyze + tests (+ minimum test count)
flutter analyze >/tmp/$T.an 2>&1 || { status=FAIL; why="$why analyze"; }
flutter test >/tmp/$T.te 2>&1 || { status=FAIL; why="$why tests"; }
tests=$(grep -oE '\+[0-9]+' /tmp/$T.te | tail -1 | tr -d +); tests=${tests:-0}
[ "$tests" -ge "${tmin:-0}" ] || { status=FAIL; why="$why tests $tests<$tmin"; }
secs=$(( $(date +%s) - t0 ))
if [ $status = OK ]; then git add -A -- ${files//,/ } && git commit -q -m "$T ($finding): $title" && sha=$(git rev-parse --short HEAD); else sha=-; fi
printf '| %s | %s | %s | %s | %s | %s | %ss | %s |\n' "$(date +%F)" "$T" "$runner" "$status${why:+ ($why)}" "$tests" "$lines" "$secs" "$sha" | tee -a tasks/LOG.md
[ $status = OK ] || { echo "rollback: git checkout -- . && git clean -fd -- lib test (logs /tmp/$T.log /tmp/$T.an /tmp/$T.te)"; exit 1; }
