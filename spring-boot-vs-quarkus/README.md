# Spring Boot vs Quarkus, JVM and native

One small notes service (add, get, update, list by tag) written twice: once with Spring Boot, once with Quarkus. Each version is written the way that framework's own docs suggest. Both run on the JVM and as a GraalVM native image, so there are four candidates. Same DigitalOcean machines, same Postgres, same k6 load, default settings everywhere.

## What runs

| | Spring Boot 4.1.2 | Quarkus 3.40.1.2 |
|---|---|---|
| Web | Spring MVC | Quarkus REST |
| Data | Spring Data JPA | Hibernate ORM with Panache |
| Pool | HikariCP | Agroal |

- JVM images run on Java 27, native images are built with GraalVM 25 (the newest GraalVM is Java 25 based).
- Same endpoints, same table (`V1__notes.sql`, Flyway), same pool size: 20 connections.
- No tuning flags. Virtual threads are off in Spring because that is the default.
- `bench/parity.sh` checks that both apps answer the same requests the same way.

## Machines (DigitalOcean, lon1)

| Machine | Size | Runs |
|---|---|---|
| sbq-app | c-2 (2 dedicated vCPU, 4 GB) | the app container, node_exporter, cAdvisor |
| sbq-db | c-4 (4 dedicated vCPU, 8 GB) | Postgres, postgres_exporter |
| sbq-load | c-8 (8 dedicated vCPU, 16 GB) | builds the images, k6, Prometheus, Grafana |

The machines talk over the private network.

## How a round runs (`bench/run.sh`)

For each variant:
1. Remove old containers, drop the OS page cache, drop and recreate the table.
2. Start the container and time `docker run` to the first `200` (`first_ok_ms`). The framework's own "started in" log line is saved too.
3. Idle memory from `docker stats`.
4. Seed 200,000 rows, `vacuum analyze`.
5. k6 with 100 virtual users, no think time: read, write, mixed (80% read, 20% write), 5 minutes each.

Round 1 runs Spring JVM, Quarkus JVM, Spring native, Quarkus native. Round 2 runs them in reverse order. Round 3 (`bench/run3.sh`, `WARM=10m`) runs the two JVM variants again after 10 minutes of unmeasured mixed load, so the JIT compiler has warmed up.

## Results

Requests per second (k6 `http_reqs.rate`) and p95 latency, from `results/r*/<variant>/<test>.json`. Every test had 0 failed requests.

| Variant | Read | Write | Mixed |
|---|---:|---:|---:|
| Spring JVM, r1 / r2 | 1,549 / 1,541 · 195 ms | 2,001 / 1,971 · 174 ms | 3,481 / 3,485 · 98 ms |
| Quarkus JVM, r1 / r2 | 5,959 / 6,087 · 42 ms | 2,715 / 3,179 · 76 ms | 6,436 / 6,564 · 33 ms |
| Spring native, r1 / r2 | 2,368 / 2,381 · 129 ms | 2,137 / 2,165 · 160 ms | 2,279 / 2,301 · 139 ms |
| Quarkus native, r1 / r2 | 4,955 / 4,907 · 41 ms | 2,801 / 2,777 · 66 ms | 4,114 / 4,099 · 51 ms |
| Spring JVM, warmed (r3) | 3,600 · 93 ms | 3,344 · 105 ms | 3,738 · 90 ms |
| Quarkus JVM, warmed (r3) | 8,017 · 26 ms | 4,438 · 43 ms | 6,559 · 33 ms |

(p95 shown for round 1, or round 3 for the warmed rows.)

During the 10-minute warm-up, Spring JVM went from 793 to 2,115 requests per second (per-minute averages) and was still climbing at the end. Quarkus JVM levelled off around minute 7. See `results/series.json`.

Startup, `docker run` to the first `200` (ms, r1 / r2): Spring JVM 15,081 / 15,387, Quarkus JVM 6,729 / 6,718, Spring native 1,327 / 1,375, Quarkus native 965 / 960. Idle memory and the framework's own startup time are in each `startup.json`.

Build on the c-8 machine (`results/build.json`): Spring JVM 54 s, Spring native 392 s, Quarkus JVM 49 s, Quarkus native 245 s. `build.json` holds the image content size; `results/docker-images.txt` is the `docker images` size on the app machine (586 / 299 / 564 / 216 MB).

These numbers hold for this app on a 2-vCPU machine with default settings. They say nothing about bigger machines, tuned JVMs, virtual threads or other workloads.

## Run it yourself

You need `doctl` logged in to your own DigitalOcean account and an SSH key there.

```sh
cd bench
SSH_KEY_NAME=<your DO ssh key name> bash create.sh   # three droplets, IPs go to files, never printed
bash go.sh                                            # copies code and scripts, runs the setup scripts
# on sbq-load: build the four images, then the rounds
APP=<app private ip> bash build.sh
APP=<app private ip> DB=<db private ip> ROUND=1 bash run.sh
```

The Grafana dashboards used during the test are in `bench/grafana`. Delete the droplets when you are done.
