#!/usr/bin/env bash
# Eirdom — fix Traefik middleware references in compose labels.
#
# Two fixes:
#   1) bare middleware names in Docker labels resolve as @docker and fail,
#      because the middlewares are defined in middlewares.yml (@file).
#      -> append @file to each file-provider middleware name.
#   2) webserver references 'adminer-ipallowlist' which doesn't exist;
#      the real middleware is 'ipallowlist-corporate'. -> rename + @file.
#
# Idempotent: names that already carry an @provider suffix are left alone.
# Run from ~/eirdom/docker.  Edits *.yml in place after a .bak backup.

set -euo pipefail

# middlewares that live in the FILE provider (from middlewares.yml)
FILE_MW="authentik security-headers rate-limit rate-limit-auth www-redirect ipallowlist-corporate chain-standard chain-public chain-admin"

shopt -s nullglob
mapfile -t composes < <(find . -name 'docker-compose.yml' -not -path '*/node_modules/*')

echo "Backing up and patching ${#composes[@]} compose files..."
for f in "${composes[@]}"; do
  cp "$f" "$f.bak"

  # Fix 2 first: wrong name -> correct name (still bare; @file added in Fix 1)
  sed -i 's/adminer-ipallowlist/ipallowlist-corporate/g' "$f"

  # Fix 1: only operate on the value of a *.middlewares= label line.
  # For each file-provider middleware, append @file when it appears as a bare
  # token (preceded by = or , and followed by , or " or end-of-line).
  for mw in $FILE_MW; do
    # value boundary cases: =mw  ,mw  mw"  mw,  end
    sed -i -E "s/(\.middlewares=[^\"]*[=,]?)(${mw})(@file)?([,\"]|\$)/\1\2@file\4/g" "$f"
  done

  # The regex above can double up if @file already present; collapse any @file@file
  sed -i 's/@file@file/@file/g' "$f"

  if ! diff -q "$f" "$f.bak" >/dev/null; then
    echo "  patched: $f"
  else
    echo "  (no change): $f"; rm -f "$f.bak"
  fi
done

echo ""
echo "=== Verify: any remaining BARE middleware refs? (should be none) ==="
grep -rn 'traefik\.http\.routers\..*\.middlewares=' . | while IFS= read -r line; do
  val=${line##*.middlewares=}; val=${val%\"}
  oldIFS=$IFS; IFS=','; bad=""
  for t in $val; do case "$t" in *@*|"") : ;; *) bad="$bad $t";; esac; done
  IFS=$oldIFS
  [ -n "$bad" ] && echo "  STILL BARE: ${line%%:*} ->$bad"
done
echo "(no 'STILL BARE' lines above = clean)"
echo ""
echo "Backups saved as *.yml.bak — remove with: find . -name '*.yml.bak' -delete"
