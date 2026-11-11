package no.pgr301.exam.config;

import io.micrometer.cloudwatch2.CloudWatchConfig;
import io.micrometer.cloudwatch2.CloudWatchMeterRegistry;
import io.micrometer.core.instrument.Clock;
import io.micrometer.core.instrument.config.MeterFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cloudwatch.CloudWatchAsyncClient;

import java.time.Duration;
import java.util.List;

@Configuration
public class MetricsConfig {

    // Cost control: CloudWatch bills per metric, so only these prefixes are sent.
    private static final List<String> ALLOWED_PREFIXES = List.of(
            "wishifai.",            // our own metrics
            "http.server.requests", // HTTP latency
            "jvm.memory.used",      // JVM memory
            "jvm.gc.pause"          // GC time
    );

    @Bean
    public CloudWatchAsyncClient cloudWatchAsyncClient(@Value("${aws.region}") String region) {
        return CloudWatchAsyncClient.builder().region(Region.of(region)).build();
    }

    @Bean
    public CloudWatchConfig cloudWatchConfig(@Value("${app.metrics.namespace}") String namespace) {
        return new CloudWatchConfig() {
            @Override
            public String get(String key) {
                return null;
            }

            // Was "", which CloudWatch rejects.
            @Override
            public String namespace() {
                return namespace;
            }

            @Override
            public Duration step() {
                return Duration.ofMinutes(1);
            }
        };
    }

    @Bean
    public CloudWatchMeterRegistry cloudWatchMeterRegistry(CloudWatchConfig config,
                                                           CloudWatchAsyncClient client) {
        CloudWatchMeterRegistry registry = new CloudWatchMeterRegistry(config, Clock.SYSTEM, client);
        registry.config().meterFilter(MeterFilter.denyUnless(id ->
                ALLOWED_PREFIXES.stream().anyMatch(id.getName()::startsWith)));
        return registry;
    }
}
