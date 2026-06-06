# Arkansas AllStarLink Node Map

A self-contained, single-file interactive map of Arkansas AllStarLink nodes with
**live** online/offline status, county overlay, last-keyed activity, a node
connection explorer, and an NWS high-impact-warning watch board with
audible/visual alarms.

`index.html` has **no backend** — every live feature runs in the browser against
public APIs (AllStarLink, NWS `api.weather.gov`, OpenStreetMap tiles, county
GeoJSON). You can open it locally by double-clicking, or host it anywhere that
serves a static file.

## Features
- Live node status (auto-refresh 60s) with All / Online / Offline filter
- Arkansas county boundary overlay
- "Last-keyed activity" watch — flags on-air / recently-active nodes
- Connection inspector: the **65017** AUXCOMM-hub button, an **any-node** input
  box (plots out-of-state/international links too), per-popup "open this node's
  connections" links, and a **Back** button to retrace hops
- **High-impact warnings** overlay (NWS): CONSIDERABLE / PDS / EMERGENCY /
  CATASTROPHIC polygons for Arkansas + bordering states, colored by tier
- **County watch list** governing alarms: all Arkansas counties by default, plus
  an input box to add out-of-state counties. New watched warnings trigger an
  audible tone + flashing banner + screen flash + tab-title flash (+ optional
  desktop notification); a mute toggle is provided. Unwatched warnings still
  display (dashed) but stay silent.

> **Note on positions:** node markers are placed at the *registered city
> centroid* (Arkansas) or operator-registered coordinates (inspected nodes) —
> **not** the actual physical repeater/antenna sites.

## Repository layout
```
index.html                  # the deployable map (generated; commit it)
scripts/build.sh            # fetch registry -> geocode new cities -> regenerate
scripts/generate_map.sh     # turns data/ into index.html
data/city_coords.txt        # geocode cache (committed; makes rebuilds fast)
.github/workflows/rebuild.yml  # daily auto-rebuild + commit
.do/app.yaml                # DigitalOcean App Platform static-site spec
```

## Deploy on DigitalOcean (App Platform — static site)
1. Push this folder to a new GitHub repo.
2. In DigitalOcean: **Create → Apps → GitHub**, pick the repo/branch.
   App Platform detects `.do/app.yaml` (a static site, `index.html`). Or edit
   `repo:` in that file and run `doctl apps create --spec .do/app.yaml`.
3. It builds and serves over HTTPS with a free `*.ondigitalocean.app` domain
   (add your own domain anytime). Static sites have a free tier.

Alternatives: upload `index.html` to **Spaces + CDN**, or serve it with
nginx/Apache on a **Droplet**.

## Auto-rebuild (keeps the node registry current)
The map's *live* data (status, connections, warnings) updates in the browser,
but the embedded list of registered nodes is a snapshot. `rebuild.yml` refreshes
it automatically:
- Runs daily (and on demand via **Actions → Run workflow**).
- Re-pulls the registry, geocodes only **newly**-registered cities (the cache
  means most runs geocode nothing), regenerates `index.html`, and commits.
- With `deploy_on_push: true`, that commit auto-redeploys the site.

Set one repo secret so outbound requests identify you politely:
**Settings → Secrets and variables → Actions → New repository secret**
`CONTACT_UA` = `your-app-name (you@example.com)`

## Rebuild locally
```bash
bash scripts/build.sh        # needs bash + curl
```

## Production considerations
- **OpenStreetMap tiles:** the map uses OSM's public tile servers, fine for
  EOC/internal or low-traffic use but **not** for heavy public traffic. For a
  high-traffic public site switch the `L.tileLayer` URL to a provider
  (MapTiler/Mapbox free tier) or self-host tiles.
- **NWS / Nominatim User-Agent:** browsers send their own UA for the live NWS
  calls (works as-is). The build script's `CONTACT_UA` is courtesy for the
  server-side registry/geocode fetches.
- No API keys or secrets are embedded; safe in a public repo.

## Data sources
- Node directory: `https://allmondb.allstarlink.org/allmondb.php`
- Live status feed: `https://allstarmap.org/all_online_nodes.js`
- Node stats/connections: `https://stats.allstarlink.org/api/stats/{node}`
- Weather alerts: `https://api.weather.gov/alerts/active`
- Counties: US Census county GeoJSON (filtered to FIPS `05`)
- Geocoding (build-time): OpenStreetMap Nominatim
