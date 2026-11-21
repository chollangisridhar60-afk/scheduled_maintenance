#!/bin/bash
# Patch ONE Amazon Linux advisory on the packages passed in by the pipeline.
# Intended for SSM Run Command (AWS-RunShellScript) in a maintenance window.
# Inputs (exported by a preamble that Terraform prepends; see main.tf):
#   ADVISORY   required  e.g. ALAS2023-2026-3478 (AL2023) or ALAS2-2026-4123 (AL2)
#   PACKAGES   required  space-separated package names; every installed package whose name
#                        starts with one of them is updated (e.g. "java-17-amazon-corretto"
#                        also covers -headless, -devel, -jmods, ...)
#   RELEASEVER optional  AL2023 only, e.g. 2023.12.20261117 (default "latest")
#   RESTART_SERVICES     1 (default): after patching, restart ONLY services whose running processes still
#                        map a replaced file of the patched packages (Java -> libjvm; brotli -> usually none,
#                        so no downtime). 0: never restart, just report (exit 2 if anything is still stale).
#                        A stale ActiveMQ that was started outside systemd is restarted through
#                        activemq.service when that unit exists; any other non-service JVM is listed for manual restart.
# No-op if the advisory belongs to the other Amazon Linux version or no listed package is installed.
# Exit codes: 0 ok, 1 update/restart failed, 2 processes still run old files (restart skipped or failed).
set -uo pipefail
log() { echo "[$(date -u +%FT%TZ)] $*"; }
ADVISORY="${ADVISORY:-}"
PACKAGES="${PACKAGES:-}"
RELEASEVER="${RELEASEVER:-latest}"
RESTART_SERVICES="${RESTART_SERVICES:-1}"
if [ -z "$ADVISORY" ] || [ -z "$PACKAGES" ]; then
  log "ERROR: ADVISORY and PACKAGES must be set."; exit 1
fi
if grep -q 'PLATFORM_ID="platform:al2023"' /etc/os-release; then
  PLATFORM=al2023; PM=dnf
elif grep -q '^PRETTY_NAME="Amazon Linux 2"' /etc/os-release; then
  PLATFORM=al2; PM=yum
else
  log "Not Amazon Linux 2/2023, nothing to do."; exit 0
fi
case "$ADVISORY" in
  ALAS2023-*) WANT=al2023 ;;
  ALAS2-*)    WANT=al2 ;;
  *) log "ERROR: unrecognised advisory '$ADVISORY'."; exit 1 ;;
esac
if [ "$PLATFORM" != "$WANT" ]; then
  log "${ADVISORY} is for ${WANT}, this host is ${PLATFORM}; nothing to do."; exit 0
fi
RC=0
PATCHED=0
# all installed packages (incl. subpackages) matching the requested names
PKGS=()
while read -r n; do
  [ -n "$n" ] && PKGS+=("$n")
done < <(for p in $PACKAGES; do rpm -qa --qf '%{NAME}\n' "${p}*"; done | sort -u)
if [ ${#PKGS[@]} -eq 0 ]; then
  log "None of (${PACKAGES}) are installed. Nothing to do."; exit 0
fi
FILELIST=$(mktemp); trap 'rm -f "$FILELIST"' EXIT
rpm -ql "${PKGS[@]}" 2>/dev/null >> "$FILELIST"   # files of the OLD versions
log "Installed: $(rpm -q "${PKGS[@]}" | tr '\n' ' ')"
log "Applying ${ADVISORY} to: ${PKGS[*]}"
if [ "$PLATFORM" = al2023 ]; then
  "$PM" -y update --advisory "$ADVISORY" --releasever "$RELEASEVER" "${PKGS[@]}"
else
  "$PM" -y update --advisory "$ADVISORY" "${PKGS[@]}"
fi
if [ $? -ne 0 ]; then
  log "ERROR: ${PM} update failed."
  RC=1
else
  PATCHED=1
  rpm -ql "${PKGS[@]}" 2>/dev/null >> "$FILELIST" # files of the NEW versions
  log "Post-update: $(rpm -q "${PKGS[@]}" | tr '\n' ' ')"
fi
# Running processes keep the OLD file mapped (shown as "(deleted)") until restarted.
# Only processes that map a replaced file of the packages patched above count, so a package
# that needs no restart (e.g. brotli with no running user) restarts nothing.
sort -u -o "$FILELIST" "$FILELIST"
stale_procs() {  # prints "pid unit" for every process still mapping a replaced file
  local pid
  for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    [ "$pid" = "$$" ] && continue
    awk '/ \(deleted\)$/ {print $6}' "/proc/$pid/maps" 2>/dev/null | grep -qxFf "$FILELIST" || continue
    echo "$pid $(ps -o unit= -p "$pid" 2>/dev/null | tr -d ' ')"
  done
}
STALE=0
STALE_UNITS=()
MANUAL=()
log "Processes still using replaced files of the patched packages:"
while read -r pid unit; do
  [ -z "$pid" ] && continue
  STALE=1
  log "  PID $pid ($(ps -o comm= -p "$pid" 2>/dev/null); ${unit:-no unit}) running old files"
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
done < <(stale_procs)
if [ $STALE -eq 0 ]; then
  log "None. No service restart needed."
elif [ $RC -ne 0 ]; then
  log "Update errors occurred; skipping service restarts."
elif [ "$RESTART_SERVICES" != 1 ]; then
  log "RESTART_SERVICES=0: restarts skipped. Services: ${STALE_UNITS[*]:-none}; other processes (pid:scope): ${MANUAL[*]:-none}"
  log "WARNING: patched packages are NOT active in these processes until they are restarted."
  [ $RC -eq 0 ] && RC=2
else
  for u in $(printf '%s\n' "${STALE_UNITS[@]}" | sort -u); do
    log "Restarting $u"
    systemctl restart "$u" || { log "ERROR: restart of $u failed"; RC=1; }
  done
  [ ${#MANUAL[@]} -gt 0 ] && log "MANUAL RESTART NEEDED (not a systemd service) pid:scope -> ${MANUAL[*]}"
  sleep 5
  REMAIN=$(stale_procs | awk '{print $1}' | tr '\n' ' ')
  if [ -n "$REMAIN" ]; then
    log "Still on old files: PIDs ${REMAIN}"
    [ $RC -eq 0 ] && RC=2
  else
    log "No stale processes remain."
  fi
fi
# Kernel/glibc/systemd-type updates need a reboot, never done automatically here (informational only)
if [ "$PLATFORM" = al2023 ]; then NR="dnf needs-restarting"; else NR="needs-restarting"; fi
if $NR --help >/dev/null 2>&1 && ! $NR -r >/dev/null 2>&1; then
  log "NOTE: the system reports a REBOOT is required (needs-restarting -r). Schedule one."
fi
log "Done."
exit $RC
