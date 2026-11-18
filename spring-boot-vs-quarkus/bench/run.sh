#!/usr/bin/env bash
# Runs on sbq-load. For each variant: fresh database, start (time to first 200), idle memory, 200k rows, then read / write / mixed for DUR each.
#   APP=<ip> DB=<ip> DUR=5m ROUND=1 VARIANTS="spring-jvm quarkus-jvm spring-native quarkus-native" bash run.sh  ->  /root/results/r<ROUND>/<variant>/
set -uo pipefail
DUR=${DUR:-5m}; N=200000; R=/root/results/r${ROUND:-1}; mkdir -p $R
SA="ssh -i /root/.ssh/sbq -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR root@$APP"
SD="ssh -i /root/.ssh/sbq -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR root@$DB"
K6ENV="K6_PROMETHEUS_RW_SERVER_URL=http://127.0.0.1:9090/api/v1/write K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true K6_PROMETHEUS_RW_PUSH_INTERVAL=1s"
PSQL="psql postgresql://notes:notes@$DB:5432/notes -qtAX"
mark() { $SA "printf 'sbq_phase{app=\"$1\",phase=\"$2\",round=\"${ROUND:-1}\"} 1\n' > /var/lib/prometheus/node-exporter/sbq.prom.tmp && mv /var/lib/prometheus/node-exporter/sbq.prom.tmp /var/lib/prometheus/node-exporter/sbq.prom"
         echo "$1 $2 $(date -u +%FT%TZ)" | tee -a $R/phases.log > $R/state; }
mem() { $SA "docker stats --no-stream --format '{{.MemUsage}}' sbq-$1" | awk '{print $1}'; }
for v in ${VARIANTS:-spring-jvm quarkus-jvm spring-native quarkus-native}; do
  mkdir -p $R/$v; mark none gap
  $SA "docker rm -f \$(docker ps -aq --filter name=sbq-) >/dev/null 2>&1; sync; echo 3 > /proc/sys/vm/drop_caches"
  $PSQL -c 'drop table if exists notes, flyway_schema_history' 2>&1 | grep -v NOTICE
  $SD "docker exec pg psql -U notes -qc checkpoint"; sleep 20
  mark $v start; t0=$(date +%s%N)
  $SA "docker run -d --name sbq-$v --network host -e APP_NAME=$v -e DB_URL=jdbc:postgresql://$DB:5432/notes sbq-$v >/dev/null"
  until curl -sf -o /dev/null "http://$APP:8080/notes?tag=java"; do sleep 0.02; done
  t1=$(date +%s%N); sleep 2
  log=$($SA "docker logs sbq-$v 2>&1")
  fw=$(grep -oE 'Started NotesApplication in [0-9.]+ seconds|started in [0-9.]+s' <<<"$log" | grep -oE '[0-9.]+' | head -1)
  jq -n --arg v $v --argjson first_ok_ms $(( (t1 - t0) / 1000000 )) --arg fw "$fw" --arg mem_start "$(mem $v)" \
     '{variant:$v, first_ok_ms:$first_ok_ms, framework_started_s:($fw|tonumber? // null), mem_after_start:$mem_start}' > $R/$v/startup.json
  jq -c . $R/$v/startup.json
  $PSQL -c "insert into notes (title, body, tag, created_at)
            select 'Note ' || g || ' about ' || (array['java','spring','postgres','k6','grafana','docker','linux','jvm'])[1 + g % 8],
                   repeat('Seeded note body for the framework test. ', 4), (array['java','spring','postgres','k6','grafana','docker','linux','jvm'])[1 + g % 8], now()
            from generate_series(1, $N) g" && $PSQL -c "vacuum analyze notes"
  mark $v idle; sleep 60; jq --arg m "$(mem $v)" '.mem_idle=$m' $R/$v/startup.json > $R/$v/s.tmp && mv $R/$v/s.tmp $R/$v/startup.json
  for mode in read write mixed; do
    mark $v $mode
    env $K6ENV TARGET=http://$APP:8080 MODE=$mode APP_NAME=$v N=$N DUR=$DUR k6 run --quiet -o experimental-prometheus-rw \
        --summary-export $R/$v/$mode.json /root/load.js > $R/$v/$mode.log 2>&1
    echo "$v $mode $(jq -c '{rps: .metrics.http_reqs.rate|floor, p95: .metrics.http_req_duration["p(95)"], p99: .metrics.http_req_duration["p(99)"], failed: .metrics.http_req_failed.value}' $R/$v/$mode.json) mem=$(mem $v)"
    mark $v cool; sleep 15
  done
  $SA "docker logs sbq-$v" > $R/$v/app.log 2>&1
  $SA "docker rm -f sbq-$v >/dev/null"
done
mark none done; touch $R/done
