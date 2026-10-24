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
# --- version-scope consistency (would have caught marketplace.json saying ">= 1.2") ---
vfail=0
M=.claude-plugin/marketplace.json; P=.claude-plugin/plugin.json
descs=$(python3 - "$M" "$P" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); p=json.load(open(sys.argv[2]))
print("marketplace.metadata\t"+m["metadata"]["description"])
for x in m["plugins"]: print("marketplace.plugin\t"+x["description"])
print("plugin.json\t"+p["description"])
r=json.load(open("plugin.json")); print("root.plugin.json\t"+r["description"])
print("root.plugin.json.interface\t"+r["extensions"]["com.openai"]["interface"]["shortDescription"])
cm=json.load(open(".agents/plugins/marketplace.json"))
names=[x["name"] for x in cm["plugins"]]
assert r["name"] in names and p["name"]==r["name"], "plugin names differ across manifests"
for x in cm["plugins"]:
  assert x["source"]["path"].startswith("./"), "codex source.path must start with ./"
  assert {"installation","authentication"} <= set(x.get("policy",{})) and x.get("category"), "codex entry needs policy.installation/authentication + category"
vs={m["version"],p["version"],r["version"]}|{x["version"] for x in m["plugins"]}
assert len(vs)==1, f"manifest versions differ: {vs}"
PY
)
descs+=$'\n'"SKILL.md"$'\t'"$(tr '\n' ' ' <<<"$desc")"$'\n'"SKILL.md.compat"$'\t'"$(grep -m1 '^compatibility:' "$S")"$'\n'"openai.yaml"$'\t'"$(grep -E 'short_description|default_prompt' $R/agents/openai.yaml | tr '\n' ' ')"
while IFS=$'\t' read -r src d; do
  [ -z "$src" ] && continue
  if grep -qE '>= ?1\.[0-9]|1\.[0-9]\+ only|Terragrunt 1\.x only|\(>= ?1' <<<"$d"; then echo "FAIL stale '>= 1.x' scope in $src: $d"; vfail=1; fi
  case $src in openai.yaml) continue;; esac
  grep -q '0\.68' <<<"$d" || { echo "FAIL $src does not state 0.68+ support"; vfail=1; }
  grep -qi 'terraform' <<<"$d" && grep -qi 'opentofu' <<<"$d" || { echo "FAIL $src does not name both OpenTofu and Terraform"; vfail=1; }
done <<<"$descs"
# README compatibility section and AGENTS must agree
grep -q 'Terragrunt 0\.68+' README.md || { echo "FAIL README compatibility lacks Terragrunt 0.68+"; vfail=1; }
grep -q 'version-compatibility.md' AGENTS.md || { echo "FAIL AGENTS.md does not list version-compatibility.md"; vfail=1; }
# stale scope claims anywhere user-facing (CHANGELOG is historical)
if grep -rnE 'Terragrunt \(?>= ?1\.2\)?|Terragrunt 1\.x only' README.md AGENTS.md .claude-plugin .agents plugin.json "$R" evaluations; then echo "FAIL stale '>= 1.2' scope claim"; vfail=1; fi
# Terragrunt flags must not be forwarded after `--`
if grep -rnE 'run --all -- backend|run --all -- [a-z]+ .*--(provider-cache|filter|non-interactive|backend-bootstrap)' "$R" "$S" README.md | grep -v 'Do not use'; then echo "FAIL Terragrunt flag/command after --"; vfail=1; fi
# auto-provisioning was removed in 0.87
if grep -rniE 'automatically (create|provision)s? (state|the s3)|auto-bootstraps? on first' README.md "$R" "$S"; then echo "FAIL claims auto backend provisioning (removed in 0.87)"; vfail=1; fi
# relative links + anchors in all markdown
python3 - <<'PY' || vfail=1
import re,os,glob,sys
def slug(h): h=re.sub(r'[`*]','',h.strip().lower()); h=re.sub(r'[^\w\- ]','',h); return h.replace(' ','-')
bad=0
for f in [f for f in glob.glob('**/*.md',recursive=True) if not f.startswith('test-output')]:
  t=re.sub(r'```.*?```','',open(f).read(),flags=re.S)
  for u in re.findall(r'\]\(([^)\s]+)\)',t):
    if u.startswith(('http','mailto')): continue
    p,_,a=u.partition('#'); tgt=os.path.normpath(os.path.join(os.path.dirname(f),p)) if p else f
    if not os.path.exists(tgt): print("FAIL broken link",f,u); bad=1; continue
    if a and tgt.endswith('.md'):
      hs=[slug(h) for h in re.findall(r'^#+ (.*)$',re.sub(r'```.*?```','',open(tgt).read(),flags=re.S),re.M)]
      if a not in hs: print("FAIL broken anchor",f,u); bad=1
sys.exit(bad)
PY
[ "$vfail" -eq 0 ] || exit 1
echo OK
