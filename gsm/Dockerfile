# Pile 2G (GSM/EDGE) Osmocom pour le Fishball 7010 flashé avec tezuka-fishball-ts
# (bitstream horodaté + démon sdr_ip_gadget). Logiciel installé, AUCUNE configuration active :
# les fichiers d'exemple sont dans /usr/share/doc/pluto-gsm/ et ne sont pas utilisés tels quels.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg build-essential git cmake pkg-config autoconf automake libtool \
      libfftw3-dev libusb-1.0-0-dev libtalloc-dev libsctp-dev libaio-dev \
      libiio-dev libiio-utils libsoapysdr-dev soapysdr-tools \
      iproute2 iptables iputils-ping net-tools procps tmux telnet less nano \
    && rm -rf /var/lib/apt/lists/*

# Dépôt Osmocom « latest » (versions récentes, CSD, correctifs ; recommandé par les mainteneurs
# plutôt que les paquets Ubuntu de 2022)
RUN curl -fsSL https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_24.04/Release.key \
      | gpg --dearmor -o /usr/share/keyrings/osmocom-latest.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/osmocom-latest.gpg] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_24.04/ ./" \
      > /etc/apt/sources.list.d/osmocom-latest.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      libosmocore-dev \
      osmo-bts-trx osmo-bsc osmo-msc osmo-hlr osmo-mgw osmo-stp \
      osmo-pcu osmo-sgsn osmo-ggsn \
      libosmocore-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# libad9361 v0.3 (gestion de l'AD936x par Soapy)
RUN git clone --depth 1 -b v0.3 https://github.com/analogdevicesinc/libad9361-iio.git \
 && cmake -S libad9361-iio -B libad9361-iio/build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build libad9361-iio/build -j"$(nproc)" && cmake --install libad9361-iio/build

# Pilote Soapy horodaté de Phil Greenland (UDP direct vers sdr_ip_gadget, ou USB direct)
RUN git clone --depth 1 -b sdr_gadget_timestamping https://github.com/pgreenland/SoapyPlutoSDR.git \
 && cmake -S SoapyPlutoSDR -B SoapyPlutoSDR/build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build SoapyPlutoSDR/build -j"$(nproc)" && cmake --install SoapyPlutoSDR/build \
 && ldconfig \
 && cmake -S SoapyPlutoSDR/support/test_c -B SoapyPlutoSDR/support/test_c/build \
 && cmake --build SoapyPlutoSDR/support/test_c/build \
 && install -m 0755 SoapyPlutoSDR/support/test_c/build/test_timestamp_loopback /usr/local/bin/

# osmo-trx avec pilote SoapySDR (iliasam, testé sur PlutoSky 7020 = famille Fishball)
RUN git clone https://github.com/iliasam/osmo-trx_soapy.git \
 && cd osmo-trx_soapy && git checkout cd9da9d \
 && autoreconf -fi \
 && ./configure --prefix=/usr/local --without-uhd --without-lms --with-soapy-trx --disable-werror \
 && make -j"$(nproc)" && make install \
 && mkdir -p /usr/share/doc/pluto-gsm \
 && cp -r Osmocom_configs /usr/share/doc/pluto-gsm/exemples-iliasam \
 && cp Transceiver52M/test1.cfg /usr/share/doc/pluto-gsm/osmo-trx-soapy.test1.cfg \
 && cd / && rm -rf /src/*/build

COPY osmo-trx-soapy.cfg.modele /usr/share/doc/pluto-gsm/osmo-trx-soapy.cfg.modele
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["aide"]
