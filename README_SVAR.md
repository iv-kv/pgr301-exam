# PGR301 Eksamen 2026 — Besvarelse

**Kandidatnummer:** 38

---

## Oppgave 1 — Container og CI

### 1A — Containerisering

`Dockerfile` bruker **multi-stage build**:

1. **Build-stage** (Maven + JDK 21): laster ned avhengigheter fra `pom.xml` i et eget lag (caches), og bygger deretter JAR-filen.
2. **Runtime-stage** (kun JRE 21 på Alpine): inneholder bare ferdig JAR-fil — ingen Maven, JDK eller kildekode. Gir mindre image og færre sårbarheter. Appen kjører som en vanlig bruker, ikke root.

`.dockerignore` holder unødvendige filer (`target/`, `.git/`, `.idea/`, `infra/`, `.env` o.l.) utenfor bygget. Det gir raskere bygg og hindrer at hemmeligheter havner i imaget.

Appen lytter på port 8080 i containeren. `-p 9999:8080` gjør den tilgjengelig på **localhost:9999**.

**Bygg og kjør:**

```bash
docker build -t wishifai .

docker run --rm -p 9999:8080 \
  -e AWS_ACCESS_KEY_ID=<access-key> \
  -e AWS_SECRET_ACCESS_KEY=<secret-key> \
  -e AWS_REGION=eu-west-1 \
  -e S3_BUCKET=<bucket-navn> \
  wishifai
```

**Test:**

```bash
curl -F "image=@samples/sample_image.png" http://localhost:9999/api/analyze
```

### 1B — CI-pipeline

Workflow: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

Grønn kjøring: https://github.com/iv-kv/pgr301-exam/actions/runs/42583104926

Workflowen kjører kun ved push til `main` (også ved merge av PR). Den bygger imaget og pusher det til ECR-repoet `wishifai-38`. Kandidatnr er med i navnet for å unngå navnekollisjoner i delte klassekonto.

AWS-nøkler ligger som GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), ikke i workflow-filen.

**Tagging-strategi:** hvert image får to tagger:

- **Commit-SHA** (`github.sha`): unik og permanent. Viser nøyaktig hvilken kode som kjører, og gjør det enkelt å rulle tilbake til en tidligere versjon.
- **`latest`**: peker alltid på nyeste image. Praktisk for testing, men sier ikke hvilken versjon det er — derfor ikke nok alene.

---

## Oppgave 2 — ECS Express og IaC

### 2A — Infrastruktur for tjenesten

**URL til serveren:** https://wi-53f46ebe9d8f432183383e69acff870d.ecs.eu-west-1.on.aws

**Test:**

```bash
curl https://wi-53f46ebe9d8f432183383e69acff870d.ecs.eu-west-1.on.aws/actuator/health
curl -F "image=@samples/sample_image.png" https://wi-53f46ebe9d8f432183383e69acff870d.ecs.eu-west-1.on.aws/api/analyze
```

All Terraform-kode ligger i `infra/`:

| Fil | Innhold |
|---|---|
| `providers.tf` | AWS-provider og S3-backend |
| `variables.tf` | `region`, `candidate_number`, `image_tag` |
| `main.tf` | S3-bucket, task role og ECS Express-tjeneste |
| `outputs.tf` | `service_url` og `s3_bucket` |

**Ressurser:**

- **S3-bucket** `pgr301-wishifai-38-images` for opplastede bilder.
- **Task role** `wishifai-task-role-38` kun tillatelser appen faktisk bruker (least privilege):
  - `s3:PutObject` — i egen bucket
  - `rekognition:DetectLabels`
  - `bedrock:InvokeModel` — Claude Sonnet 4.5
- **ECS Express-tjeneste** `wishifai-38`, bruker eksisterende execution- og infrastructure-rollene fra klassekonto.

**Valg:**

- `S3_BUCKET` settes automatisk fra bucket-ressursen.
- `image_tag` har ingen default og settes til github sin commit-SHA. Da ser Terraform endring ved hver ny versjon og deployer den.
- Mindre størrelse enn default (0,5 vCPU / 1 GB i stedet for 1 vCPU / 2 GB) for å spare kostnad.
- Autoskalering begrenset til maks 2 tasks (default er 20), som sikring mot uventede kostnader.
- Health check på `/actuator/health`, siden appen ikke svarer på `/`.
- `wait_for_steady_state = true`: `apply` venter til tjenesten faktisk kjører. En ødelagt deploy gjør dermed pipelinen rød.

### 2B — Remote state

State lagres i den delte bucketen `pgr301-terraform-state` med nøkkelen:

```
wishifai/38/terraform.tfstate
```

Kandidatnummeret i nøkkelen gjør at state er unik. `use_lockfile = true` gir låsing i S3, slik at to `apply` ikke kan skrive til samme state samtidig.

### 2C — Terraform i GitHub Actions

Workflowen har nå to jobber: `build-and-push` og `terraform`. Terraform-jobben har `needs: build-and-push` og kjører:

1. `terraform fmt -check -recursive` — pipelinen feiler hvis koden ikke er formatert
2. `terraform init`
3. `terraform validate`
4. `terraform apply -auto-approve -var image_tag=<commit-SHA>`

Grønn kjøring: <LENKE>

**Terraform kjører etter container-build:** Terraform deployer imaget med taggen `<commit-SHA>`. Dette imaget må finnes i ECR før tjenesten oppdateres. Ellers kan den peke på et image som ikke finnes ennå, og deployen feiler. Med `needs:` deployes ingenting hvis bygget feiler.

---

## Oppgave 3 — Observability

### 3A — Metrikker i applikasjonen

**Oppsett:** `MetricsConfig` hadde tomt namespace (`""`), som CloudWatch avviser. Derfor feilmeldingene i loggen. Nå den er `wishifai-38`.

**Kostnadskontroll:** CloudWatch tar betalt per metrikk. Spring Boot lager over hundre metrikker automatisk, så et `MeterFilter` slipper bare gjennom de vi bruker:

- `wishifai.*` — egne metrikker
- `http.server.requests` — HTTP-latency
- `jvm.memory.used`, `jvm.gc.pause` — JVM-minne og GC-tid

**Timer:**

| Metrikk | Hva | Hvorfor |
|---|---|---|
| `wishifai.rekognition.duration` | Tid for `DetectLabels`-kallet | hvor mye tiden går til bildeanalyse |
| `wishifai.bedrock.duration` | Tid for `Converse`-kallet til Claude | hvor mye som går til LLM-en |

Timere måler kun selve AWS-kallet, ikke hele requesten. Da kan de sammenlignes direkte og vise **hvor tiden blir av**. Begge har taggen `outcome` (`success`/`error`), så feilede kall ikke blander seg med vellykkede. CloudWatch får `count`, `avg`, `max` og `sum` for hver.

**Funn:** Tre testkall mot `/api/analyze` (ca. 19 s totalt hver):

| | Snitt | Maks |
|---|---|---|
| Rekognition | ~1,3 s | 1,7 s |
| Bedrock | ~15,3 s | 16,1 s |

Bedrock står for det meste av svartiden. Prompten ber Claude resonnere i flere steg og skrive inntil 5 begrunnede forslag - grunnen er sikkert der. 

**Business-metrikker (DistributionSummary):**

| Metrikk | Hva | Hvorfor |
|---|---|---|
| `wishifai.gift.suggestions` | Antall gaveforslag per analyse | **Hovedmetrikken.** Viser om tjenesten faktisk gjør sin jobb. `count` = antall analyser, `avg` = kvalitet. `0` betyr at svaret fra Claude ikke kunne parses — en feil som ellers er usynlig, siden appen fortsatt svarer HTTP 200. |
| `wishifai.bedrock.tokens` (`type=input/output`) | Tokens per Bedrock-kall | Tokens er det vi betaler for. Output-tokens forklarer også hvorfor Bedrock er tregt. |
| `wishifai.rekognition.labels` | Antall labels per bilde | Få labels gir Claude lite å jobbe med, og forslagene blir svakere. |

### 3B — Dashboard og alarm

**Dashboard:** `wishifai-38` ([`infra/dashboard.tf`](infra/dashboard.tf))

| Rad | Innhold |
|---|---|
| Business | Antall analyser, forslag per analyse, tokens |
| Latency | Rekognition vs Bedrock, HTTP `/api/analyze` |
| Infrastruktur | ECS CPU, minne, antall tasks |
| Applikasjon | JVM heap, GC-pausetid |

**Alarm:** `wishifai-38-bedrock-slow` ([`infra/alarms.tf`](infra/alarms.tf))

Går av når snittet av `wishifai.bedrock.duration` er over **30 s** i 3 minutter på rad. Varsel (og OK når det er over) sendes på e-post via SNS.

- Bedrock er ca. 80 % av svartiden, så tregt Bedrock = treg tjeneste — akkurat det gründeren er bekymret for.
- Normalt ~15 s, så 30 s betyr en reell dobling, ikke tilfeldig variasjon.
- `treat_missing_data = notBreaching`: lite trafikk skal ikke utløse alarm.
