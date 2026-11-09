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
