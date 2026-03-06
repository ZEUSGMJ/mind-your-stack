#!/bin/bash
# opt-out-config.sh - Apply Nextcloud telemetry opt-out settings via OCC.
# Mounted into Docker entrypoint hooks (post-installation and before-starting).
# Also works standalone: docker exec mys-nextcloud-optout-app bash /opt-out-config.sh
#
# NOTE: Entrypoint hooks run as www-data, so we run php occ directly.
# When run as root (standalone), we use runuser to switch to www-data.

set -e

echo "Applying Nextcloud opt-out configuration..."

# When run via entrypoint hook, config.php already exists.
# When run standalone, wait for it.
if [ ! -f /var/www/html/config/config.php ]; then
    echo "Waiting for Nextcloud installation to complete..."
    while [ ! -f /var/www/html/config/config.php ]; do
        sleep 5
    done
    sleep 10
fi

cd /var/www/html

# Helper function to run occ commands
# If running as root, use runuser; otherwise run directly
run_occ() {
    if [ "$(id -u)" = "0" ]; then
        runuser -u www-data -- php occ "$@" 2>&1 || true
    else
        php occ "$@" 2>&1 || true
    fi
}

# Disable update checker
echo "  - Disabling update checker..."
run_occ config:system:set updatechecker --value=false --type=boolean

# Disable app store (stops apps.nextcloud.com fetches)
echo "  - Disabling app store..."
run_occ config:system:set appstoreenabled --value=false --type=boolean

# Disable has_internet_connection check
echo "  - Disabling internet connection check..."
run_occ config:system:set has_internet_connection --value=false --type=boolean

# Disable connectivity checks
echo "  - Disabling connectivity checks..."
run_occ config:system:set connectivity_check_enabled --value=false --type=boolean

# Disable .well-known setup checks (can trigger outbound connections)
echo "  - Disabling well-known setup checks..."
run_occ config:system:set check_for_working_wellknown_setup --value=false --type=boolean

# Disable the survey_client app (monthly usage statistics)
echo "  - Disabling survey_client app..."
run_occ app:disable survey_client

# Disable updatenotification app (checks for updates)
echo "  - Disabling updatenotification app..."
run_occ app:disable updatenotification

# Disable firstrunwizard (can fetch external resources)
echo "  - Disabling firstrunwizard app..."
run_occ app:disable firstrunwizard

# Disable support app (can phone home)
echo "  - Disabling support app..."
run_occ app:disable support

# Disable recommendations app (fetches external app data)
echo "  - Disabling recommendations app..."
run_occ app:disable recommendations

echo ""
echo "Opt-out configuration applied. Verifying settings:"
echo "  updatechecker: $(run_occ config:system:get updatechecker)"
echo "  appstoreenabled: $(run_occ config:system:get appstoreenabled)"
echo "  has_internet_connection: $(run_occ config:system:get has_internet_connection)"
echo "  connectivity_check_enabled: $(run_occ config:system:get connectivity_check_enabled)"
echo "  check_for_working_wellknown_setup: $(run_occ config:system:get check_for_working_wellknown_setup)"
echo ""
echo "Disabled apps:"
run_occ app:list --disabled | grep -E "survey_client|updatenotification|firstrunwizard|support|recommendations" || echo "  (none matched or check manually)"
