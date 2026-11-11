package no.pgr301.exam.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import no.pgr301.exam.model.GiftAnalysis;
import no.pgr301.exam.model.GiftSuggestion;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.ContentBlock;
import software.amazon.awssdk.services.bedrockruntime.model.ConversationRole;
import software.amazon.awssdk.services.bedrockruntime.model.ConverseRequest;
import software.amazon.awssdk.services.bedrockruntime.model.ConverseResponse;
import software.amazon.awssdk.services.bedrockruntime.model.Message;

import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
public class BedrockService {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final Pattern JSON_OBJECT = Pattern.compile("\\{.*}", Pattern.DOTALL);

    private final BedrockRuntimeClient client;
    private final String modelId;
    private final MeterRegistry registry;

    public BedrockService(BedrockRuntimeClient client,
                          @Value("${app.bedrock.model-id}") String modelId,
                          MeterRegistry registry) {
        this.client = client;
        this.modelId = modelId;
        this.registry = registry;
    }

    /**
     * Denne måten å lage prompt på kalles "chain-of-thought" og kan være veldig effektivt
     * Dette er også et eksempel på negative prompting
     * @param labels
     * @return
     */
    public GiftAnalysis suggestGifts(List<String> labels) {
        String prompt = """
                Du er en gaveassistent. Du får en liste med objekter som Rekognition
                oppdaget i et bilde av et rom eller en gjenstand. Oppgaven din er å
                foreslå gaver som passer for personen som eier rommet.

                Objekter: %s

                Tenk gjennom disse stegene før du svarer:

                1. ROM-ANALYSE: Hva slags rom eller miljø er dette sannsynligvis?
                   Se etter mønstre i objektene — er det en stue, et barnerom, en
                   garasje, et kjøkken? Hva slags stil eller interesser signaliserer
                   gjenstandene?

                2. MOTTAKER-PROFIL: Hvem bruker rommet? Trekk konklusjoner om alder,
                   livssituasjon og interesser basert på det du ser. Vær spesifikk,
                   men ikke overdriv — hvis du er usikker, si det.

                3. GAVER: Basert på analysen over, foreslå inntil 5 gaver som faktisk
                   passer for denne personen. **Prøv å navngi reelle produkter eller
                   merker** der det er mulig. Unngå generiske forslag som "en bok"
                   eller "et gavekort".

                Eksempler på bra gaveforslag (format og konkretisering):

                - "Lego DC Batmobile 76240" — spesifikk SKU, konkret produkt
                - "Alessi Juicy Salif-sitronpresser" — merke + produktnavn
                - "Matchbox Volvo FH-truck" — merke + modell
                - "Røros Tweed Islandsk ullpledd" — merke + produktlinje
                - "Rains Backpack Mini (sort)" — merke + modell + variant

                Eksempler på DÅRLIGE forslag (for generiske):

                - "en lekebil"
                - "et pledd"
                - "en pen vase"
                - "noe fra en interiørbutikk"

                Svar KUN med gyldig JSON på dette formatet:
                {
                  "roomAnalysis": "kort beskrivelse av rommet og hva det signaliserer",
                  "recipientProfile": "antagelser om personen (alder, interesser, livssituasjon)",
                  "suggestions": [
                    {"gift": "konkret gaveforslag", "reasoning": "hvorfor denne gaven passer basert på profilen"}
                  ]
                }
                """.formatted(String.join(", ", labels));

        // Measures only the AWS call. Outcome tag splits successful and failed calls.
        Timer.Sample sample = Timer.start(registry);
        String outcome = "success";
        ConverseResponse resp;
        try {
            resp = client.converse(ConverseRequest.builder()
                    .modelId(modelId)
                    .messages(Message.builder()
                            .role(ConversationRole.USER)
                            .content(ContentBlock.fromText(prompt))
                            .build())
                    .build());
        } catch (RuntimeException e) {
            outcome = "error";
            throw e;
        } finally {
            sample.stop(Timer.builder("wishifai.bedrock.duration")
                    .description("Time spent in Bedrock Converse")
                    .tag("outcome", outcome)
                    .register(registry));
        }

        recordTokens(resp);

        String text = resp.output().message().content().get(0).text();
        return parseAnalysis(text);
    }

    // Tokens per call. Output tokens drive both Bedrock latency and cost.
    private void recordTokens(ConverseResponse resp) {
        if (resp.usage() == null) {
            return;
        }
        tokens("input").record(resp.usage().inputTokens());
        tokens("output").record(resp.usage().outputTokens());
    }

    private DistributionSummary tokens(String type) {
        return DistributionSummary.builder("wishifai.bedrock.tokens")
                .description("Bedrock tokens per call")
                .baseUnit("tokens")
                .tag("type", type)
                .register(registry);
    }

    // Business metric: gift suggestions per analysis. 0 means the answer could not be parsed.
    private void recordSuggestions(int count) {
        DistributionSummary.builder("wishifai.gift.suggestions")
                .description("Gift suggestions per analysis")
                .register(registry)
                .record(count);
    }

    private GiftAnalysis parseAnalysis(String text) {
        try {
            Matcher m = JSON_OBJECT.matcher(text);
            String json = m.find() ? m.group() : text;
            GiftAnalysis analysis = MAPPER.readValue(json, GiftAnalysis.class);
            recordSuggestions(analysis.suggestions() == null ? 0 : analysis.suggestions().size());
            return analysis;
        } catch (Exception e) {
            recordSuggestions(0);
            return new GiftAnalysis(
                    "(ukjent)",
                    "(kunne ikke parse svar)",
                    List.of(new GiftSuggestion("(ukjent format)", text))
            );
        }
    }
}
