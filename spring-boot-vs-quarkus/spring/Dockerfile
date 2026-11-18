# Spring Boot 4.1.2, two targets from one source:  docker build --target jvm|native -t sbq-spring-<target> .
FROM eclipse-temurin:27-jdk AS build-jvm
WORKDIR /src
COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN ./mvnw -q -B dependency:go-offline
COPY src src
RUN ./mvnw -q -B -DskipTests package

FROM eclipse-temurin:27-jre AS jvm
WORKDIR /app
COPY --from=build-jvm /src/target/notes.jar notes.jar
EXPOSE 8080 9091
ENTRYPOINT ["java", "-jar", "notes.jar"]

FROM ghcr.io/graalvm/native-image-community:25i5-25.0.5.0.3 AS build-native
WORKDIR /src
COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN ./mvnw -q -B -Pnative dependency:go-offline
COPY src src
RUN ./mvnw -q -B -Pnative -DskipTests native:compile

FROM debian:trixie-slim AS native
WORKDIR /app
COPY --from=build-native /src/target/notes notes
EXPOSE 8080 9091
ENTRYPOINT ["./notes"]
