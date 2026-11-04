# Image de compilation : arduino-cli et les cores ESP32 et RP2040 installés une fois pour toutes.
# Le conteneur tourne ensuite SANS réseau (voir runner.dart) : tout ce qui sert à compiler doit être ici.
#
#   docker build -t nomad-compiler:latest -f docker/Dockerfile docker
#
# Pour des compilations reproductibles, figer les versions :
#   docker build --build-arg ESP32_CORE=3.1.1 --build-arg RP2040_CORE=4.4.2 ...
FROM ubuntu:24.04

ARG ARDUINO_CLI_VERSION=
ARG ESP32_CORE=
ARG RP2040_CORE=

ENV DEBIAN_FRONTEND=noninteractive \
    ARDUINO_DIRECTORIES_DATA=/opt/arduino/data \
    ARDUINO_DIRECTORIES_USER=/opt/arduino/user \
    ARDUINO_DIRECTORIES_DOWNLOADS=/opt/arduino/staging \
    ARDUINO_UPDATER_ENABLE_NOTIFICATION=false

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh \
    | BINDIR=/usr/local/bin sh -s ${ARDUINO_CLI_VERSION}

RUN arduino-cli config init \
 && arduino-cli config add board_manager.additional_urls https://espressif.github.io/arduino-esp32/package_esp32_index.json \
 && arduino-cli config add board_manager.additional_urls https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json \
 && arduino-cli core update-index \
 && arduino-cli core install "esp32:esp32${ESP32_CORE:+@$ESP32_CORE}" \
 && arduino-cli core install "rp2040:rp2040${RP2040_CORE:+@$RP2040_CORE}" \
 && rm -rf /opt/arduino/staging \
 && mkdir -p /opt/arduino/user/libraries \
 && chmod -R a+rX /opt/arduino

WORKDIR /work
