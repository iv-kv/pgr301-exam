# Stage 1: build
# Full JDK + Maven. Only used to produce JAR file during build phase.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build

# a layer caching trick, so dependencies are cached and not re-downloaded when only source code changes.
# If we change only Java code, pom.xml is unchanged, Docker reuses the cached dependency layer, and the rebuild takes seconds.
COPY pom.xml .
RUN mvn -q dependency:go-offline

# Copies the source code and builds the JAR into target/.
#-DskipTests skips tests in the image build. TODO - change after tests are written.
COPY src ./src
RUN mvn -q package -DskipTests



# Stage 2: run
# JRE only -> smaller and lightweight image, less attack surface.
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Run as an unprivileged user instead of root.
# If someone exploited the app, they'd be root inside the container.
RUN addgroup -S app && adduser -S app -G app
USER app

# Copying finished jar file from build stage.
COPY --from=build /build/target/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
