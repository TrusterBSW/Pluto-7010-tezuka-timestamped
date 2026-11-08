# srsRAN 4G + SoapyPlutoSDR horodaté (Quantulum / pgreenland) pour le Fishball 7010
# flashé avec tezuka-fishball-ts (bitstream fishball_ts_iio + sdr_ip_gadget).
#
# Versions alignées sur l'article de Phil Greenland (Private LTE with Pluto+ SDR),
# sauf Ubuntu 22.04 et libiio 0.26 (version présente côté carte dans Tezuka).
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake git pkg-config ca-certificates \
      libfftw3-dev libmbedtls-dev libboost-program-options-dev libconfig++-dev \
      libsctp-dev libzstd-dev libxml2-dev libaio-dev libusb-1.0-0-dev \
      libavahi-client-dev libavahi-common-dev flex bison \
      iproute2 iptables iputils-ping net-tools procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# libiio (côté PC) : contrôle de l'AD9363 via iiod sur la carte
RUN git clone --depth 1 -b v0.26 https://github.com/analogdevicesinc/libiio.git \
 && cmake -S libiio -B libiio/build -DCMAKE_BUILD_TYPE=Release -DWITH_IIOD=OFF \
      -DWITH_TESTS=OFF -DWITH_DOC=OFF -DPYTHON_BINDINGS=OFF -DCPP_BINDINGS=OFF \
      -DWITH_SERIAL_BACKEND=OFF -DHAVE_DNS_SD=ON \
 && cmake --build libiio/build -j"$(nproc)" && cmake --install libiio/build

RUN git clone --depth 1 -b v0.3 https://github.com/analogdevicesinc/libad9361-iio.git \
 && cmake -S libad9361-iio -B libad9361-iio/build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build libad9361-iio/build -j"$(nproc)" && cmake --install libad9361-iio/build

RUN git clone --depth 1 -b soapy-sdr-0.8.1 https://github.com/pothosware/SoapySDR.git \
 && cmake -S SoapySDR -B SoapySDR/build -DCMAKE_BUILD_TYPE=Release -DENABLE_PYTHON3=OFF \
 && cmake --build SoapySDR/build -j"$(nproc)" && cmake --install SoapySDR/build

# Pilote Soapy avec horodatage (UDP direct vers sdr_ip_gadget, ou USB direct)
# Correctif : avec hostname=, se connecter directement (le scan « ip » passe par Avahi/DNS-SD, absent
# du conteneur ; il échoue et srsRAN, qui énumère avant d'ouvrir, ne trouvait pas la carte)
COPY soapy-hostname-first.patch /tmp/soapy-hostname-first.patch
RUN git clone --depth 1 -b sdr_gadget_timestamping https://github.com/pgreenland/SoapyPlutoSDR.git \
 && patch -d SoapyPlutoSDR -p1 < /tmp/soapy-hostname-first.patch \
 && cmake -S SoapyPlutoSDR -B SoapyPlutoSDR/build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build SoapyPlutoSDR/build -j"$(nproc)" && cmake --install SoapyPlutoSDR/build \
 && ldconfig

# srsRAN 4G (EPC + eNB), débits LTE standard (1.92 / 3.84 / 7.68 MS/s)
RUN git clone --depth 1 -b release_23_04 https://github.com/srsran/srsRAN_4G.git \
 && cmake -S srsRAN_4G -B srsRAN_4G/build -DCMAKE_BUILD_TYPE=Release -DUSE_LTE_RATES=ON \
      -DENABLE_UHD=OFF -DENABLE_BLADERF=OFF -DENABLE_ZEROMQ=OFF -DENABLE_SOAPYSDR=ON \
      -DENABLE_GUI=OFF -DENABLE_SRSUE=OFF \
 && cmake --build srsRAN_4G/build -j"$(nproc)" && cmake --install srsRAN_4G/build \
 && ldconfig && srsran_install_configs.sh service \
 && rm -rf /src/*/build

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
WORKDIR /root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["all"]
