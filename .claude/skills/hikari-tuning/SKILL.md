---
name: hikari-tuning
description: Configure HikariCP explicitly (pool size, timeouts, leak detection) instead of relying on Spring Boot's implicit defaults, and prove it works under concurrent load.
---

# hikari-tuning

Spring Boot autoconfigures HikariCP with sane-but-implicit defaults
(`maximum-pool-size=10`, `minimum-idle=10`, 30s connection timeout, 10min
idle timeout, 30min max lifetime, leak detection off). Implicit is fine
until you need to reason about saturation under load — make it explicit so
it's documented, tunable, and visible in Grafana.

Apply this once the datasource exists (right after `crud`, or alongside
`dockerization`/`observability-grafana`).

## 1. Explicit configuration

In `application.properties` (adapt the numbers to the actual workload —
these are reasonable defaults for a small service, not universal
constants):

```properties
spring.datasource.hikari.pool-name=<ServiceName>HikariPool
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=5
spring.datasource.hikari.connection-timeout=20000
spring.datasource.hikari.idle-timeout=300000
spring.datasource.hikari.max-lifetime=1200000
spring.datasource.hikari.leak-detection-threshold=30000
```

- `pool-name`: give it one — the default (`HikariPool-1`) is indistinguishable
  across services in shared dashboards/logs.
- `leak-detection-threshold`: enable it (0 = disabled is the Spring Boot
  default) — cheap in dev/test, catches connections that never get closed.
- Tune `maximum-pool-size` against the actual DB's own connection limit and
  expected concurrency, not a copy-pasted number.

## 2. Verification test

A single `@SpringBootTest` class proving the config is real, not just
present in a properties file:

```java
@SpringBootTest
class HikariConnectionPoolTest {

    @Autowired private DataSource dataSource;
    @Autowired private SomeRepository repository;

    @Test
    void shouldConfigureHikariDataSourceWithTheProjectDefaults() {
        HikariDataSource hikari = (HikariDataSource) dataSource;
        assertThat(hikari.getPoolName()).isEqualTo("<ServiceName>HikariPool");
        assertThat(hikari.getMaximumPoolSize()).isEqualTo(10);
        // ... one assertion per configured property
    }

    @Test
    void shouldServeMoreConcurrentCallersThanThePoolSizeWithoutConnectionErrors() throws InterruptedException {
        int maximumPoolSize = ((HikariDataSource) dataSource).getMaximumPoolSize();
        int concurrentCallers = maximumPoolSize * 3; // force queueing past the pool limit

        ExecutorService executor = Executors.newFixedThreadPool(concurrentCallers);
        CountDownLatch ready = new CountDownLatch(concurrentCallers);
        CountDownLatch start = new CountDownLatch(1);
        Callable<Long> hitTheDb = () -> { ready.countDown(); start.await(); return repository.count(); };

        List<Future<Long>> futures = new ArrayList<>();
        for (int i = 0; i < concurrentCallers; i++) futures.add(executor.submit(hitTheDb));
        ready.await(5, TimeUnit.SECONDS);
        start.countDown();

        for (Future<Long> f : futures) assertThatCode(() -> f.get(15, TimeUnit.SECONDS)).doesNotThrowAnyException();
        executor.shutdown();
    }
}
```

The second test is the one that actually matters: it proves Hikari queues
callers beyond the pool size instead of throwing
`SQLTransientConnectionException: Connection is not available`. A
config-values-only test can pass while the pool is still misconfigured for
real concurrency (e.g. `connection-timeout` too low for the expected queue
depth) — this catches that class of bug.

## 3. Make it visible in Grafana

If `observability-grafana` is also applied, the Hikari pool already exposes
`hikaricp_connections_active/idle/pending/max` to Prometheus — add a
utilization gauge (`active ÷ max`) alongside the existing timeseries; see
that skill's dashboard section for the exact panel JSON.

## Verify, don't claim

Run the test class and read the actual pool log line on startup
(`<PoolName> - Starting...` / `Added connection ...`) to confirm the
configured name and size took effect — not just that the test file compiles.
