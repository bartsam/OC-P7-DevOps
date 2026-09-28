# ==============
# Build versions
# ==============
ARG NODE_VERSION=20-alpine
ARG CADDY_VERSION=2-alpine
ARG GRADLE_VERSION=8.7-jdk17
ARG JAVA_VERSION=17-jre

# =======================
# Stage 1: Build Frontend
# =======================

# Use a lightweight Node.js image for building
FROM node:${NODE_VERSION} AS front-build

# Set the working directory inside the container
WORKDIR /src

# Copy package-related files to leverage Docker's caching mechanism
COPY front/package.json front/package-lock.json ./

# Install project dependencies 
RUN --mount=type=cache,target=/root/.npm npm ci

# Copy the application source code into the container
COPY front/ ./

# Build the Angular application
RUN npm run build

# ======================
# Stage 2: Build Backend
# ======================

# Use a JDK image for building (customizable via ARG)
FROM gradle:${GRADLE_VERSION} AS back-build

# Set the working directory inside the container
WORKDIR /src

# Copy the application source code into the container
COPY back/ ./

# Compile and package the executable Spring Boot JAR
RUN ./gradlew build

# =========================
# Stage 3: Runtime Frontend
# =========================

# Use a lightweight Caddy image for runtime
FROM caddy:${CADDY_VERSION} AS front

# Set the working directory inside the container
WORKDIR /app

# Copy the static build output from the build stage to Caddy's default HTML serving directory
COPY --from=front-build /src/dist/microcrm/browser /app/front

# Copy custom Caddy config
COPY misc/docker/Caddyfile /app/Caddyfile

# Serve the frontend over HTTP for local orchestration.
EXPOSE 80

# Start Caddy directly with custom config
CMD ["caddy", "run", "--config", "/app/Caddyfile", "--adapter", "caddyfile"]

# ========================
# Stage 4: Runtime Backend
# ========================

# Use a lightweight JRE image for runtime
FROM eclipse-temurin:${JAVA_VERSION} AS back

# Set the working directory inside the container
WORKDIR /app

# Create a dedicated non-root user and group for running the application
RUN addgroup --system spring && adduser --system --ingroup spring spring

# Copy the packaged JAR from the build stage to the runtime image and Ensure non-root user owns the application files
COPY --from=back-build --chown=spring:spring /src/build/libs/microcrm-0.0.1-SNAPSHOT.jar /app/back/microcrm-0.0.1-SNAPSHOT.jar

# Switch to the non-root user for security best practices
USER spring:spring

# Document that the application listens on port 8080
EXPOSE 8080

# Start the Spring Boot application (executable JAR with embedded server)
CMD ["java", "-jar", "/app/back/microcrm-0.0.1-SNAPSHOT.jar"]
