#!/usr/bin/env bash
set -euo pipefail

exec 9>/run/lock/helios-watch-auth.lock
flock -n -E 2 9

blocked=$(firewall-cmd --ipset=helios-blacklist --get-entries)
candidates=$(
  journalctl -u sshd.service --since '-10 min' -o cat --no-pager |
    awk '
      /^Invalid user / || /^Failed (password|publickey) for / {
        if ($0 ~ /^Failed .* for invalid user /) next
        for (i = 1; i < NF; i++) {
          if ($i == "from" && $(i+1) ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $(i+2) == "port") {
            count[$(i+1)]++
            break
          }
        }
      }
      END {
        for (ip in count)
          if (count[ip] > 5 && ip != "192.168.56.1")
            print ip, count[ip]
      }'
)

while read -r ip count; do
  [[ -n "$ip" ]] || continue
  if grep -Fxq "$ip" <<< "$blocked"; then
    continue
  fi
  firewall-cmd --ipset=helios-blacklist --add-entry="$ip"
  logger -t helios-watch-auth "Blocked $ip after $count SSH failures in 10 minutes"
done <<< "$candidates"
