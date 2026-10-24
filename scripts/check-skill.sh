#!/usr/bin/env bash
set -euo pipefail
R=skills/terragrunt-skill; S=$R/SKILL.md
# description = indented block after "description: |" up to next top-level key / closing ---
desc=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^description:/{d=1;sub(/^description:[ |>-]*/,"");if(length)print;next} d&&/^[a-z_-]+:/{d=0} d{sub(/^  /,"");print}' "$S")
n=${#desc}; echo "description chars: $n"; [ "$n" -gt 0 ] && [ "$n" -le 1024 ] || { echo "FAIL desc len $n"; exit 1; }
lines=$(wc -l < "$S"); [ "$lines" -lt 500 ] || { echo "FAIL SKILL.md >=500 lines"; exit 1; }
rc=0; grep -rnE -- '--experiment[= ](dependency-fetch-output-from-state|block-iteration|oci|mutable-generate|cas)' "$R" || rc=$?
case $rc in 0) echo "FAIL stale experiment flag"; exit 1;; 1) :;; *) echo "FAIL grep error $rc"; exit 2;; esac
fail=0
while read -r f; do f=${f%%#*}; [ -f "$R/$f" ] || { echo "FAIL missing $f"; fail=1; }; done < <(grep -oE '\]\((references|assets)/[^)]+\)' "$S" | sed -E 's/^\]\(//; s/\)$//')
[ "$fail" -eq 0 ] || exit 1
echo OK
