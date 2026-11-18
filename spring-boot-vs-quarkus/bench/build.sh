#!/usr/bin/env bash
# Runs on sbq-load (8 vCPU, 16 GB): builds the four images from /root/src/{spring,quarkus}, times each build, ships them to the app machine.
#   APP=<private ip> bash build.sh   ->  /root/results/build.json
set -euo pipefail; R=/root/results; mkdir -p $R; echo '{}' > $R/build.json
for app in spring quarkus; do for t in jvm native; do
  s=$(date +%s); docker build -q --target $t -t sbq-$app-$t /root/src/$app >/dev/null; e=$(( $(date +%s) - s ))
  size=$(docker image inspect sbq-$app-$t --format '{{.Size}}')
  jq --arg k $app-$t --argjson s $e --argjson b $size '.[$k]={build_s:$s, image_bytes:$b}' $R/build.json > $R/b.tmp && mv $R/b.tmp $R/build.json
  echo "$app-$t built in ${e}s, $((size/1000000)) MB"
done; done
docker save sbq-spring-jvm sbq-spring-native sbq-quarkus-jvm sbq-quarkus-native | ssh -i /root/.ssh/sbq -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR root@$APP docker load
