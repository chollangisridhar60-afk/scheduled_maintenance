#!/bin/bash
# Patch CVE-2026-114938 (OpenJDK Base64 decoder memory corruption, Corretto 17/21/25/27)
#   AL2023: ALAS2023-2026-3478 (17), -3479 (21), -3480 (25), -3481 (27)
#   AL2   : ALAS2-2026-4123 (17 only)
# Intended for SSM Run Command (AWS-RunShellScript) in a maintenance window.
# No-op if none of the affected packages are installed.
# Optional env: RELEASEVER (AL2023 only, default "latest").
#   RESTART_SERVICES=0  skip restarts (default 1: restart systemd services whose JVM still runs the old
#                       libjvm). A stale ActiveMQ that was started outside systemd is restarted through
#                       activemq.service when that unit exists; any other non-service JVM is listed for manual restart.
# Exit codes: 0 ok, 1 update/restart failed, 2 stale JVMs remain after restart.
set -uo pipefail
RELEASEVER="${RELEASEVER:-latest}"
RESTART_SERVICES="${RESTART_SERVICES:-1}"
log() { echo "[$(date -u +%FT%TZ)] $*"; }
# major version -> advisory, per platform
declare -A ADV_AL2023=( [17]="ALAS2023-2026-3478" [21]="ALAS2023-2026-3479" [25]="ALAS2023-2026-3480" [27]="ALAS2023-2026-3481" )
declare -A ADV_AL2=( [17]="ALAS2-2026-4123" )
if grep -q 'PLATFORM_ID="platform:al2023"' /etc/os-release; then
  PLATFORM=al2023; PM=dnf; declare -n ADV=ADV_AL2023
elif grep -q '^PRETTY_NAME="Amazon Linux 2"' /etc/os-release; then
  PLATFORM=al2; PM=yum; declare -n ADV=ADV_AL2
else
  log "Not Amazon Linux 2/2023, nothing to do."; exit 0
fi
RC=0
PATCHED=0
for major in 17 21 25 27; do
  # all subpackages (headless, devel, jmods, ...) of this Corretto major
  mapfile -t PKGS < <(rpm -qa --qf '%{NAME}\n' "java-${major}-amazon-corretto*" | sort -u)
  [ ${#PKGS[@]} -eq 0 ] && continue
  advisory="${ADV[$major]:-}"
  if [ -z "$advisory" ]; then
    log "Corretto ${major} installed but no advisory for ${PLATFORM}; skipping."
    continue
  fi
  log "Corretto ${major} installed: $(rpm -q "${PKGS[@]}" | tr '\n' ' ')"
  log "Applying ${advisory} to: ${PKGS[*]}"
  if [ "$PLATFORM" = al2023 ]; then
    "$PM" -y update --advisory "$advisory" --releasever "$RELEASEVER" "${PKGS[@]}"
  else
    "$PM" -y update --advisory "$advisory" "${PKGS[@]}"
  fi
  if [ $? -ne 0 ]; then
    log "ERROR: ${PM} update failed for Corretto ${major}."
    RC=1
    continue
  fi
  PATCHED=1
  log "Post-update: $(rpm -q "${PKGS[@]}" | tr '\n' ' ')"
done
if [ $PATCHED -eq 0 ] && [ $RC -eq 0 ]; then
  log "No affected Corretto 17/21/25/27 packages installed. Nothing to do."
  exit 0
fi
# Running JVMs keep the old libjvm mapped until restarted
stale_jvms() {  # prints "pid unit" for every java process with the old libjvm mapped
  local pid
  for pid in $(pgrep -x java 2>/dev/null); do
    if grep -q 'libjvm.so (deleted)' "/proc/$pid/maps" 2>/dev/null; then
      echo "$pid $(ps -o unit= -p "$pid" 2>/dev/null | tr -d ' ')"
    fi
  done
}
STALE=0
STALE_UNITS=()
MANUAL=()
log "Java processes still using a replaced JDK:"
while read -r pid unit; do
  [ -z "$pid" ] && continue
  STALE=1
  log "  PID $pid (${unit:-no unit}) running stale JVM"
  if [[ "$unit" == *.service ]]; then
    STALE_UNITS+=("$unit")
  elif tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'activemq' \
       && systemctl cat activemq.service >/dev/null 2>&1; then
    # ActiveMQ started outside systemd (e.g. from a login shell); its init script/unit can restart it
    log "  PID $pid is ActiveMQ outside systemd; will restart via activemq.service"
    STALE_UNITS+=("activemq.service")
  else
    MANUAL+=("$pid:${unit:-none}")
  fi
done < <(stale_jvms)
if [ $STALE -eq 0 ]; then
  log "No stale JVMs."
elif [ $RC -ne 0 ]; then
  log "Update errors occurred; skipping service restarts."
elif [ "$RESTART_SERVICES" != 1 ]; then
  log "RESTART_SERVICES=0: restarts skipped. Services: ${STALE_UNITS[*]:-none}; non-service JVMs (pid:scope): ${MANUAL[*]:-none}"
else
  for u in $(printf '%s\n' "${STALE_UNITS[@]}" | sort -u); do
    log "Restarting $u"
    systemctl restart "$u" || { log "ERROR: restart of $u failed"; RC=1; }
  done
  [ ${#MANUAL[@]} -gt 0 ] && log "MANUAL RESTART NEEDED (not a systemd service) pid:scope -> ${MANUAL[*]}"
  sleep 5
  REMAIN=$(stale_jvms | awk '{print $1}' | tr '\n' ' ')
  if [ -n "$REMAIN" ]; then
    log "Still on old JVM: PIDs ${REMAIN}"
    [ $RC -eq 0 ] && RC=2
  else
    log "No stale JVMs remain."
  fi
fi
log "Done."
exit $RC