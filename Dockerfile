# syntax=docker/dockerfile:1

# =============================================================================
# MicroCRM - Multi-stage Dockerfile
#
# Targets:
#   - front       : static Angular app served by Caddy
#   - back        : Spring Boot API on a minimal JRE
#   - standalone   : front + back in a single image (supervisor)
#
# Base images are pinned to explicit tags for reproducible builds.
# BuildKit cache mounts are used to speed up npm / Gradle dependency resolution.
# =============================================================================

# -----------------------------------------------------------------------------
# Frontend build stage
# -----------------------------------------------------------------------------
FROM node:22-alpine AS front-build

WORKDIR /src

# Copy manifests first so the (slow) dependency install layer is cached
# and only re-run when package.json / package-lock.json change.
COPY front/package.json front/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

# Copy the rest of the sources and build the production bundle.
COPY front/ ./
RUN npm run build

# -----------------------------------------------------------------------------
# Backend build stage
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk AS back-build

WORKDIR /src

# Copy the Gradle wrapper and build scripts first to cache dependency resolution.
COPY back/gradlew ./
COPY back/gradle ./gradle
COPY back/build.gradle back/settings.gradle ./
RUN chmod +x gradlew

# Copy sources and build the executable (Spring Boot) jar.
COPY back/src ./src
RUN --mount=type=cache,target=/root/.gradle ./gradlew --no-daemon clean bootJar \
    && cp build/libs/*.jar /app.jar

# -----------------------------------------------------------------------------
# Frontend runtime stage (static files served by Caddy)
# -----------------------------------------------------------------------------
FROM caddy:2-alpine AS front

COPY --from=front-build /src/dist/microcrm/browser /app/front
COPY misc/docker/Caddyfile /etc/caddy/Caddyfile

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://localhost/ || exit 1

# The official Caddy image already runs: caddy run --config /etc/caddy/Caddyfile

# -----------------------------------------------------------------------------
# Backend runtime stage (Spring Boot on a minimal Alpine JRE, non-root)
#   Image Alpine officielle Adoptium : ~286 Mo (vs ~479 Mo pour la variante Ubuntu),
#   busybox wget inclus (utilise par le HEALTHCHECK), pas d'outils superflus.
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine AS back

WORKDIR /app

# Utilisateur non privilegie (moindre privilege). Syntaxe Alpine (busybox).
RUN addgroup -S spring && adduser -S -G spring spring
USER spring:spring

COPY --from=back-build /app.jar /app/microcrm.jar

EXPOSE 8080

# GET sur la racine Spring Data REST (renvoie 200). Forme portable busybox wget.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8080/ || exit 1

ENTRYPOINT ["java", "-jar", "/app/microcrm.jar"]

# -----------------------------------------------------------------------------
# Standalone stage (front + back in one image, orchestrated by supervisor)
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine AS standalone

RUN apk add --no-cache caddy supervisor

WORKDIR /app

COPY --from=front-build /src/dist/microcrm/browser /app/front
COPY --from=back-build /app.jar /app/back/microcrm.jar
COPY misc/docker/Caddyfile /etc/caddy/Caddyfile
COPY misc/docker/supervisor.ini /app/supervisor.ini

EXPOSE 80 8080

CMD ["supervisord", "-c", "/app/supervisor.ini"]
