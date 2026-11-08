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

**Bygg ogGood kjør:**

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
