#!/bin/bash
# Patch ALAS2023-2026-3334 (CVE-2026-111497, brotli) on Amazon Linux 2023.
# Intended for SSM Run Command (AWS-RunShellScript) in a maintenance window.
# No-op if none of the affected packages are installed.
set -uo pipefail
ADVISORY="ALAS2023-2026-3334"
RELEASEVER="2023.12.20261026"
CANDIDATES=(brotli libbrotli brotli-devel python3-brotli)
log() { echo "[$(date -u +%FT%TZ)] $*"; }
# Only run on Amazon Linux 2023
if ! grep -q 'PLATFORM_ID="platform:al2023"' /etc/os-release; then
  log "Not Amazon Linux 2023, nothing to do."
  exit 0
fi
# Find which affected packages are installed
INSTALLED=()
for pkg in "${CANDIDATES[@]}"; do
  if rpm -q "$pkg" >/dev/null 2>&1; then
    INSTALLED+=("$pkg")
  fi
done
if [ ${#INSTALLED[@]} -eq 0 ]; then
  log "None of (${CANDIDATES[*]}) are installed. Nothing to do."
  exit 0
fi
log "Installed affected packages:"
rpm -q "${INSTALLED[@]}"
# Update only the installed packages, restricted to this advisory
log "Applying ${ADVISORY} to: ${INSTALLED[*]}"
if ! dnf -y update --advisory "$ADVISORY" --releasever "$RELEASEVER" "${INSTALLED[@]}"; then
  log "ERROR: dnf update failed."
  exit 1
fi
log "Post-update versions:"
rpm -q "${INSTALLED[@]}"
# Report (do not perform) restarts needed for processes still using old libs
if command -v dnf >/dev/null 2>&1; then
  log "Processes that may need a restart:"
  dnf needs-restarting 2>/dev/null | grep -i brotli || log "None detected for brotli."
fi
log "Done."
exit 0
