#!/usr/bin/env bash
# Rebuild index.html from the live AllStarLink registry.
# Pipeline: fetch node directory -> filter Arkansas -> geocode only NEW cities
# (cached in data/city_coords.txt) -> regenerate the self-contained map.
# Note: deliberately NOT using -e/pipefail — the geocode pipelines use grep|head,
# where grep exits non-zero via SIGPIPE and would abort the run.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DATA="$ROOT/data"
CACHE="$DATA/city_coords.txt"
OUT="$ROOT/index.html"
# Nominatim + NWS both ask for an identifying User-Agent with a contact.
UA="${CONTACT_UA:-ar-allstar-map/1.0 (set CONTACT_UA env to your email/URL)}"

mkdir -p "$DATA"
touch "$CACHE"

echo "[1/3] Fetching AllStarLink node directory..."
curl -fsS -A "$UA" "https://allmondb.allstarlink.org/allmondb.php" -o "$DATA/allmondb.txt"
# Match Arkansas whether registered as ", AR" or ", Arkansas" (case-insensitive) —
# the old ", AR"-only filter silently dropped nodes like "Springdale, Arkansas".
grep -iE '\|[^|]*,[[:space:]]*(AR|Arkansas)[[:space:]]*$' "$DATA/allmondb.txt" > "$DATA/ar_nodes.txt" || true
echo "      Arkansas nodes: $(wc -l < "$DATA/ar_nodes.txt")"

echo "[2/3] Geocoding new cities (incremental; cached cities are skipped)..."
# canonical city key (UPPER, state stripped, spaces squeezed) — must match generate_map.sh
awk -F'|' '{print $4}' "$DATA/ar_nodes.txt" \
  | tr '[:lower:]' '[:upper:]' \
  | sed -E 's/[[:space:]]*,?[[:space:]]*(AR|ARKANSAS)[[:space:]]*$//; s/[[:space:]]+/ /g; s/^ //; s/ $//' \
  | sort -u > "$DATA/cities.txt"
have="$(cut -d'|' -f1 "$CACHE")"
new=0
while IFS= read -r city; do
  [ -z "$city" ] && continue
  if printf '%s\n' "$have" | grep -qxF "$city"; then continue; fi
  enc=$(printf '%s' "$city" | sed 's/ /%20/g')
  resp=$(curl -fsS -A "$UA" "https://nominatim.openstreetmap.org/search?city=${enc}&state=Arkansas&country=USA&format=json&limit=1" || true)
  lat=$(printf '%s' "$resp" | grep -oE '"lat":"[^"]+"' | head -1 | sed -E 's/.*:"([^"]+)"/\1/')
  lon=$(printf '%s' "$resp" | grep -oE '"lon":"[^"]+"' | head -1 | sed -E 's/.*:"([^"]+)"/\1/')
  if [ -z "$lat" ]; then   # fallback to free-text query (handles typos / unincorporated places)
    resp=$(curl -fsS -A "$UA" "https://nominatim.openstreetmap.org/search?q=${enc}%2C%20Arkansas%2C%20USA&format=json&limit=1" || true)
    lat=$(printf '%s' "$resp" | grep -oE '"lat":"[^"]+"' | head -1 | sed -E 's/.*:"([^"]+)"/\1/')
    lon=$(printf '%s' "$resp" | grep -oE '"lon":"[^"]+"' | head -1 | sed -E 's/.*:"([^"]+)"/\1/')
  fi
  printf '%s|%s|%s\n' "$city" "${lat:-}" "${lon:-}" >> "$CACHE"
  new=$((new+1)); echo "      + $city -> ${lat:-MISS},${lon:-MISS}"
  sleep 1.2   # Nominatim usage policy: <= 1 request/second
done < "$DATA/cities.txt"
echo "      New cities geocoded this run: $new"

echo "[3/3] Generating index.html..."
COORDS="$CACHE" NODES="$DATA/ar_nodes.txt" bash "$HERE/generate_map.sh" "$OUT"
echo "Done."
