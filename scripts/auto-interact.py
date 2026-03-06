#!/usr/bin/env python3
"""
auto-interact.py - Automated browser interaction for Mind Your Stack experiments.

Uses Playwright to simulate realistic user interaction with self-hosted apps.
Each app has its own interaction routine that walks through setup and basic usage.

Usage: python3 scripts/auto-interact.py <experiment-name> [--timeout SECONDS]
"""

import sys
import time
import argparse
import os
from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

# Ports per experiment (must match docker-compose.yml)
APP_PORTS = {
    "n8n-single": 5678,
    "n8n-queue": 5678,
    "n8n-queue-optout-partial": 5678,
    "n8n-queue-optout-full": 5678,
    "immich": 2283,
    "immich-solo": 2283,
    "nextcloud": 18080,
    "nextcloud-solo": 18080,
    "nextcloud-optout": 18080,
}

PAUSE_SHORT = 5   # seconds between quick actions
PAUSE_MED = 8     # seconds between major actions
PAUSE_LONG = 10   # seconds for page loads


def wait(seconds, label=""):
    """Sleep with optional label for logging."""
    if label:
        print(f"  [{label}] waiting {seconds}s...")
    time.sleep(seconds)


def safe_click(page, selector, timeout=10000, label=""):
    """Click an element if it exists, swallow errors gracefully."""
    try:
        page.click(selector, timeout=timeout)
        if label:
            print(f"  Clicked: {label}")
        return True
    except (PWTimeout, Exception) as e:
        if label:
            print(f"  Skip (not found): {label} - {e.__class__.__name__}")
        return False


def safe_fill(page, selector, value, timeout=10000, label=""):
    """Fill an input if it exists."""
    try:
        page.fill(selector, value, timeout=timeout)
        if label:
            print(f"  Filled: {label}")
        return True
    except (PWTimeout, Exception) as e:
        if label:
            print(f"  Skip (not found): {label} - {e.__class__.__name__}")
        return False


def safe_goto(page, url, timeout=30000, label=""):
    """Navigate to a URL, handle timeouts."""
    try:
        page.goto(url, timeout=timeout, wait_until="domcontentloaded")
        if label:
            print(f"  Navigated: {label}")
        return True
    except (PWTimeout, Exception) as e:
        if label:
            print(f"  Navigation failed: {label} - {e}")
        return False


def interact_n8n(page, base_url):
    """
    n8n interaction: complete owner setup, browse workflow editor.
    Works for both n8n-single and n8n-queue.
    """
    print("Starting n8n interaction...")

    # Step 1: Load the app
    if not safe_goto(page, base_url, timeout=60000, label="n8n home"):
        return
    wait(PAUSE_LONG, "initial load")

    # Step 2: Setup form - n8n shows an owner setup on first visit
    # The setup form has email, first name, last name, password fields
    safe_fill(page, 'input[name="email"]', "researcher@example.com", label="email")
    wait(PAUSE_SHORT)
    safe_fill(page, 'input[name="firstName"]', "Research", label="first name")
    wait(PAUSE_SHORT)
    safe_fill(page, 'input[name="lastName"]', "User", label="last name")
    wait(PAUSE_SHORT)
    safe_fill(page, 'input[name="password"]', "ResearchPw123!", label="password")
    wait(PAUSE_SHORT)

    # Try to submit the setup form
    # n8n uses different button selectors across versions
    safe_click(page, 'button[type="submit"]', label="setup submit")
    wait(PAUSE_MED, "setup submission")

    # Step 3: Skip or dismiss any post-setup prompts
    # n8n may show a "Get started" or skip personalization dialog
    safe_click(page, 'button:has-text("Skip")', timeout=5000, label="skip prompt")
    wait(PAUSE_SHORT)
    safe_click(page, 'button:has-text("Get started")', timeout=5000, label="get started")
    wait(PAUSE_SHORT)

    # Step 4: Browse the workflow editor
    safe_goto(page, f"{base_url}/workflows", label="workflows page")
    wait(PAUSE_MED, "workflows page")

    # Step 5: Create a new workflow (triggers network calls for node types)
    safe_goto(page, f"{base_url}/workflow/new", label="new workflow")
    wait(PAUSE_MED, "new workflow editor")

    # Step 6: Click on the canvas / try to open node panel
    safe_click(page, 'button[data-test-id="node-creator-plus-button"]', timeout=5000, label="add node button")
    wait(PAUSE_SHORT)

    # Step 7: Try clicking some node categories
    safe_click(page, 'text="Action in an app"', timeout=5000, label="action in app")
    wait(PAUSE_SHORT)
    safe_click(page, 'text="Helpers"', timeout=5000, label="helpers")
    wait(PAUSE_SHORT)

    # Step 8: Visit settings pages
    safe_goto(page, f"{base_url}/settings/personal", label="settings")
    wait(PAUSE_MED, "settings page")

    safe_goto(page, f"{base_url}/settings/community-nodes", label="community nodes")
    wait(PAUSE_MED, "community nodes page")

    # Step 9: Visit templates page (may trigger external fetches)
    safe_goto(page, f"{base_url}/templates", label="templates")
    wait(PAUSE_MED, "templates page")

    print("n8n interaction complete.")


def interact_immich(page, base_url):
    """
    Immich interaction: complete admin signup, browse UI.
    """
    print("Starting Immich interaction...")

    # Step 1: Load the app
    if not safe_goto(page, base_url, timeout=60000, label="Immich home"):
        return
    wait(PAUSE_LONG, "initial load")

    # Step 2: Admin registration
    # Immich shows a registration page on first visit
    safe_click(page, 'button:has-text("Getting Started")', timeout=10000, label="getting started")
    wait(PAUSE_SHORT)

    safe_fill(page, 'input[id="email"]', "admin@example.com", label="email")
    wait(PAUSE_SHORT)
    safe_fill(page, 'input[id="password"]', "ResearchPw123!", label="password")
    wait(PAUSE_SHORT)
    safe_fill(page, 'input[id="confirmPassword"]', "ResearchPw123!", label="confirm password")
    wait(PAUSE_SHORT)
    safe_fill(page, 'input[id="name"]', "Research Admin", label="name")
    wait(PAUSE_SHORT)

    safe_click(page, 'button[type="submit"]', label="signup submit")
    wait(PAUSE_MED, "signup submission")

    # Step 3: Login if redirected to login page
    safe_fill(page, 'input[id="email"]', "admin@example.com", timeout=5000, label="login email")
    wait(PAUSE_SHORT)
    safe_fill(page, 'input[id="password"]', "ResearchPw123!", timeout=5000, label="login password")
    wait(PAUSE_SHORT)
    safe_click(page, 'button[type="submit"]', timeout=5000, label="login submit")
    wait(PAUSE_MED, "login")

    # Step 4: Dismiss onboarding if shown
    safe_click(page, 'button:has-text("Done")', timeout=5000, label="onboarding done")
    wait(PAUSE_SHORT)
    safe_click(page, 'button:has-text("OK")', timeout=5000, label="onboarding OK")
    wait(PAUSE_SHORT)

    # Step 5: Browse the UI
    safe_goto(page, f"{base_url}/photos", label="photos page")
    wait(PAUSE_MED, "photos")

    safe_goto(page, f"{base_url}/explore", label="explore page")
    wait(PAUSE_MED, "explore")

    safe_goto(page, f"{base_url}/map", label="map page")
    wait(PAUSE_MED, "map")

    safe_goto(page, f"{base_url}/sharing", label="sharing page")
    wait(PAUSE_MED, "sharing")

    # Step 6: Admin settings
    safe_goto(page, f"{base_url}/admin/system-settings", label="admin settings")
    wait(PAUSE_MED, "admin settings")

    safe_goto(page, f"{base_url}/admin/jobs-status", label="jobs status")
    wait(PAUSE_MED, "jobs status")

    safe_goto(page, f"{base_url}/admin/server-status", label="server status")
    wait(PAUSE_MED, "server status")

    print("Immich interaction complete.")


def interact_nextcloud(page, base_url):
    """
    Nextcloud interaction: wait for setup, click through files/settings/apps.
    """
    print("Starting Nextcloud interaction...")

    # Step 1: Load the app (Nextcloud can be slow to initialize)
    if not safe_goto(page, base_url, timeout=120000, label="Nextcloud home"):
        return
    wait(PAUSE_LONG, "initial load")

    # Step 2: Nextcloud auto-installs on first load with env vars set.
    # Wait for the login page or dashboard to appear.
    # With NEXTCLOUD_ADMIN_USER/PASSWORD set, it should auto-configure.
    # But we may need to wait for the installation to complete.
    print("  Waiting for Nextcloud initialization (may take a while)...")
    wait(30, "Nextcloud init")

    # Reload to check if install finished
    safe_goto(page, base_url, timeout=60000, label="reload after init")
    wait(PAUSE_LONG)

    # Step 3: Login if needed (auto-setup should have created the admin user)
    safe_fill(page, 'input[name="user"]', "admin", timeout=10000, label="username")
    wait(PAUSE_SHORT)
    safe_fill(page, 'input[name="password"]', "admin_research_pw", timeout=5000, label="password")
    wait(PAUSE_SHORT)
    safe_click(page, 'button[type="submit"]', timeout=5000, label="login submit")
    wait(PAUSE_MED, "login")

    # Step 4: Dismiss first-run wizard if present
    safe_click(page, 'button:has-text("Skip")', timeout=5000, label="skip wizard")
    wait(PAUSE_SHORT)
    safe_click(page, '.modal-container .close', timeout=5000, label="close modal")
    wait(PAUSE_SHORT)

    # Step 5: Navigate Files
    safe_goto(page, f"{base_url}/apps/files/", label="files app")
    wait(PAUSE_MED, "files")

    # Step 6: Navigate to settings
    safe_goto(page, f"{base_url}/settings/admin/overview", label="admin overview")
    wait(PAUSE_MED, "admin overview")

    # Step 7: Server info (triggers checks)
    safe_goto(page, f"{base_url}/settings/admin/serverinfo", label="server info")
    wait(PAUSE_MED, "server info")

    # Step 8: Apps page (triggers app store fetch)
    safe_goto(page, f"{base_url}/settings/apps", label="apps")
    wait(PAUSE_MED, "apps page")

    # Click through app categories
    safe_click(page, 'a:has-text("Featured")', timeout=5000, label="featured apps")
    wait(PAUSE_MED)
    safe_click(page, 'a:has-text("Security")', timeout=5000, label="security apps")
    wait(PAUSE_MED)

    # Step 9: Check for updates page
    safe_goto(page, f"{base_url}/settings/admin/overview", label="admin overview 2")
    wait(PAUSE_MED, "admin overview")

    # Step 10: User settings
    safe_goto(page, f"{base_url}/settings/user", label="user settings")
    wait(PAUSE_MED, "user settings")

    print("Nextcloud interaction complete.")


def interact_immich_solo(page, base_url):
    """
    Immich solo: expected to crash. Just try loading the page.
    """
    print("Starting Immich solo interaction (expected to fail)...")

    # Just try to load. The server is probably crash-looping.
    safe_goto(page, base_url, timeout=15000, label="Immich solo home")
    wait(PAUSE_MED, "checking if anything loads")

    # Try once more
    safe_goto(page, base_url, timeout=15000, label="Immich solo retry")
    wait(PAUSE_SHORT)

    print("Immich solo interaction complete (likely crashed, as expected).")


# Map experiment names to interaction functions
INTERACTIONS = {
    "n8n-single": interact_n8n,
    "n8n-queue": interact_n8n,
    "n8n-queue-optout-partial": interact_n8n,
    "n8n-queue-optout-full": interact_n8n,
    "immich": interact_immich,
    "immich-solo": interact_immich_solo,
    "nextcloud": interact_nextcloud,
    "nextcloud-solo": interact_nextcloud,
    "nextcloud-optout": interact_nextcloud,
}


def main():
    parser = argparse.ArgumentParser(description="Automated browser interaction for MYS experiments")
    parser.add_argument("experiment", help="Experiment name (e.g., n8n-single)")
    parser.add_argument("--timeout", type=int, default=600, help="Max interaction time in seconds (default: 600)")
    args = parser.parse_args()

    experiment = args.experiment

    if experiment not in APP_PORTS:
        print(f"Error: Unknown experiment '{experiment}'")
        print(f"Known experiments: {', '.join(APP_PORTS.keys())}")
        sys.exit(1)

    port = APP_PORTS[experiment]
    base_url = f"http://localhost:{port}"
    interact_fn = INTERACTIONS.get(experiment)

    if not interact_fn:
        print(f"No interaction defined for '{experiment}', skipping.")
        sys.exit(0)

    print(f"=== Auto-Interact: {experiment} ===")
    print(f"URL: {base_url}")
    print(f"Timeout: {args.timeout}s")
    print()

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                viewport={"width": 1280, "height": 720},
                ignore_https_errors=True,
            )
            page = context.new_page()

            # Set a global navigation timeout
            page.set_default_timeout(30000)

            interact_fn(page, base_url)

            browser.close()

        print(f"\n=== Auto-Interact complete: {experiment} ===")

    except Exception as e:
        print(f"\nAuto-Interact error for {experiment}: {e}")
        print("Continuing gracefully (interaction failure is non-fatal).")
        sys.exit(0)  # Exit 0 so run-experiment.sh doesn't abort


if __name__ == "__main__":
    main()
