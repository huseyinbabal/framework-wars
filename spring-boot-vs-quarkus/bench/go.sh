#!/usr/bin/env bash
# From the Mac: copy everything, run the three setups in the background with ready/failed markers.
set -euo pipefail; cd "$(dirname "$0")"; S="ssh -F ssh_config"
for n in sbq-app sbq-db sbq-load; do for i in $(seq 60); do $S $n true 2>/dev/null && break; sleep 5; done; done
APP=$(cat app_ip); DB=$(cat db_ip)
$S sbq-load 'test -f /root/.ssh/sbq || ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/sbq'
PUB=$($S sbq-load cat /root/.ssh/sbq.pub)
for n in sbq-app sbq-db; do $S $n "grep -qF '$PUB' /root/.ssh/authorized_keys || echo '$PUB' >> /root/.ssh/authorized_keys"; done
for n in sbq-app sbq-db sbq-load; do scp -q -F ssh_config common.sh setup-*.sh $n:/root/; done
rsync -a -e "ssh -F ssh_config" --exclude target ../spring ../quarkus sbq-load:/root/src/
scp -q -F ssh_config load.js run.sh run3.sh build.sh sbq-load:/root/
$S sbq-app "rm -f /root/ready /root/failed; nohup bash -c 'bash /root/setup-app.sh > /root/setup.log 2>&1 && touch /root/ready || touch /root/failed' >/dev/null 2>&1 &"
$S sbq-db "rm -f /root/ready /root/failed; nohup bash -c 'PRIV=$DB bash /root/setup-db.sh > /root/setup.log 2>&1 && touch /root/ready || touch /root/failed' >/dev/null 2>&1 &"
$S sbq-load "rm -f /root/ready /root/failed; nohup bash -c 'APP=$APP DB=$DB bash /root/setup-load.sh > /root/setup.log 2>&1 && touch /root/ready || touch /root/failed' >/dev/null 2>&1 &"
echo started
