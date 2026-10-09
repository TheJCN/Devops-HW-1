#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); [[ $# -lt 2 ]] || printf '       Next: %s\n' "$2"; }

printf 'Linux DevOps Homework Checker\n\n'

# 1. Unit must point at the actual application path.
execstart="$(systemctl show homework-app.service -p ExecStart --value 2>/dev/null || true)"
if grep -q '/opt/linux-devops-homework/app/server.py' <<<"$execstart"; then
  pass 'systemd ExecStart points to the application'
else
  fail 'systemd ExecStart is incorrect' 'Inspect: systemctl status homework-app; systemctl cat homework-app; ls -l /opt/linux-devops-homework /opt/linux-devops-homework/app'
fi

# 2. Service identity is part of the required state.
user="$(systemctl show homework-app.service -p User --value 2>/dev/null || true)"
group="$(systemctl show homework-app.service -p Group --value 2>/dev/null || true)"
if [[ "$user" == homework && "$group" == homework ]]; then
  pass 'service runs as homework:homework'
else
  fail 'service identity is incorrect' 'Inspect: systemctl cat homework-app; id homework'
fi

# 3. State directory must be writable without making it world-writable.
owner="$(stat -c '%U:%G' /var/lib/linux-devops-homework 2>/dev/null || true)"
mode="$(stat -c '%a' /var/lib/linux-devops-homework 2>/dev/null || true)"
if [[ "$owner" == 'homework:homework' && "$mode" == '750' ]]; then
  pass 'state directory ownership and permissions are correct'
else
  fail "state directory is $owner mode ${mode:-unknown}; expected homework:homework mode 750" 'Inspect the service journal and directory metadata: journalctl -u homework-app -n 30; namei -l /var/lib/linux-devops-homework; stat /var/lib/linux-devops-homework'
fi

# 4. Unit should be enabled and running.
if systemctl is-enabled --quiet homework-app.service 2>/dev/null; then pass 'service is enabled'; else fail 'service is not enabled' 'Inspect: systemctl is-enabled homework-app'; fi
if systemctl is-active --quiet homework-app.service 2>/dev/null; then
  pass 'service is active'
else
  fail 'service is not active' 'Inspect: systemctl status homework-app; journalctl -u homework-app -n 50 --no-pager'
fi

# 5. Verify process ownership through the running MainPID.
pid="$(systemctl show homework-app.service -p MainPID --value 2>/dev/null || true)"
if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && [[ -r "/proc/$pid/status" ]]; then
  proc_uid="$(awk '/^Uid:/{print $2}' "/proc/$pid/status")"
  homework_uid="$(id -u homework 2>/dev/null || true)"
  if [[ "$proc_uid" == "$homework_uid" ]]; then pass 'running process has the expected UID'; else fail 'running process UID is unexpected' "Inspect /proc/$pid/status and: ps -o pid,ppid,user,group,args -p $pid"; fi
else
  fail 'could not verify the service process' 'Get MainPID with: systemctl show homework-app -p MainPID; then inspect /proc/<PID> and ps'
fi

# 6. Port and bind address.
if ss -lntp 2>/dev/null | grep -Eq '0\.0\.0\.0:8080([[:space:]]|$)'; then
  pass 'TCP/8080 listens on 0.0.0.0'
elif ss -lnt 2>/dev/null | grep -Eq '127\.0\.0\.1:8080([[:space:]]|$)'; then
  fail 'TCP/8080 is reachable only through loopback' 'Inspect: ss -lntp; then inspect /etc/linux-devops-homework/app.conf and the repository config file'
else
  fail 'nothing is listening on the required TCP/8080 socket' 'Inspect: ss -lntp; systemctl status homework-app; journalctl -u homework-app -n 50'
fi

# 7. Application-level check.
health="$(curl -fsS --max-time 2 http://127.0.0.1:8080/health 2>/dev/null || true)"
if [[ "$health" == '{"status": "ok"}' ]]; then
  pass 'GET /health returns the expected response'
else
  fail 'HTTP health check failed' 'First prove the process and socket state, then test: curl -v http://127.0.0.1:8080/health'
fi

# 8. Repository files must contain the submitted solution, not only /etc changes.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if grep -q '^ExecStart=/opt/linux-devops-homework/app/server.py$' "$repo_root/systemd/homework-app.service"; then
  pass 'fixed systemd unit is saved in the repository'
else
  fail 'repository still contains the original broken unit' 'Apply the same final unit configuration to systemd/homework-app.service before committing'
fi
if grep -q '^host[[:space:]]*=[[:space:]]*0\.0\.0\.0$' "$repo_root/config/app.conf"; then
  pass 'fixed application configuration is saved in the repository'
else
  fail 'repository still contains the original bind configuration' 'Apply the same final configuration to config/app.conf before committing'
fi

printf '\nResult: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
