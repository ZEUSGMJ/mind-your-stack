# Manual Interaction Run Instructions

**Created:** 2026-02-19
**Purpose:** Run experiments with real browser interaction instead of Playwright automation

## Setup Complete

- Nextcloud trusted domains updated to allow access from 10.0.0.222
- All apps accessible via browser
- Script `run-manual.sh` handles capture and cleanup

---

## Commands

### Nextcloud (full stack)
```bash
sudo ./scripts/run-manual.sh nextcloud
```
- **URL:** http://10.0.0.222:18080
- **Login:** admin / admin_research_pw
- **Interactions:** Login, browse files, check apps page, open settings, admin panel

### Nextcloud (solo)
```bash
sudo ./scripts/run-manual.sh nextcloud-solo
```
- **URL:** http://10.0.0.222:18080
- **Login:** admin / admin_research_pw
- **Interactions:** Same as above (compare behavior)

### n8n (queue mode)
```bash
sudo ./scripts/run-manual.sh n8n-queue
```
- **URL:** http://10.0.0.222:5678
- **Login:** Create on first run
- **Interactions:** Create account, make workflow, browse templates, check settings

### n8n (single mode)
```bash
sudo ./scripts/run-manual.sh n8n-single
```
- **URL:** http://10.0.0.222:5678
- **Login:** Create on first run
- **Interactions:** Same as above (compare behavior)

### Immich (full stack)
```bash
sudo ./scripts/run-manual.sh immich
```
- **URL:** http://10.0.0.222:2283
- **Login:** Create on first run
- **Interactions:** Create account, upload photo, browse library, admin settings

### Immich (solo)
```bash
sudo ./scripts/run-manual.sh immich-solo
```
- **URL:** http://10.0.0.222:2283
- **Note:** Will crash (no database), but captures crash behavior

### Opt-out Variants (optional)
```bash
sudo ./scripts/run-manual.sh n8n-queue-optout-full
# URL: http://10.0.0.222:5678

sudo ./scripts/run-manual.sh nextcloud-optout
# URL: http://10.0.0.222:18080
# Login: admin / admin_research_pw
```

---

## Run Order (ports conflict)

Run one at a time, in this order:

1. `nextcloud` (18080)
2. `nextcloud-solo` (18080)
3. `n8n-queue` (5678)
4. `n8n-single` (5678)
5. `immich` (2283)
6. `immich-solo` (2283) - optional, will crash

---

## What Happens

1. Script starts containers and packet capture
2. You interact via browser (take your time)
3. Press Enter in terminal when done
4. Script saves pcap, extracts domains, tears down containers

---

## Output Location

Results saved to: `data/<experiment>-manual-<timestamp>/`

Files:
- `capture.pcap` - all network traffic
- `external-domains.txt` - TLS SNI domains (auto-extracted)
- `container-logs.txt` - container output

---

## After All Runs

Check results:
```bash
# List all manual runs
ls -lt data/*-manual-*/

# View domains from each run
for dir in data/*-manual-*/; do
    echo "=== $dir ==="
    cat "$dir/external-domains.txt"
    echo ""
done
```

---

## Notes

- Spend 5-10 minutes per app exploring features
- Try to trigger update checks, app store browsing, settings pages
- The goal is to see if manual interaction reveals more domains than Playwright automation
