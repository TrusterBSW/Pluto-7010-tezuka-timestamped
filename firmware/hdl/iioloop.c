// Essai des deux voies TX/RX (mode 2R2T) par rebouclage numerique AD9363, directement en libiio.
// Une voie dont seul I est active est en 8 bits (logique CS8 du FPGA) : mot 16 bits = I8 << 8 | Q8 en TX,
// Q8 << 8 | I8 en RX.
// TX1 emet une tonalite a +fs/8, TX2 a +3fs/16 : on voit ainsi si chaque voie arrive, et sur quelle voie RX.
// Usage : iioloop <uri> <masque TX voltage0..3> <masque RX voltage0..3> [amplitude 0..1]
//   ex. iioloop ip:10.5.1.96 0xf 0xf     (deux voies 16 bits)
//       iioloop ip:10.5.1.96 0x4 0xf     (TX2 seule, en 8 bits)
#include <iio.h>
#include <complex.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NTX 16384
#define NRX 65536

static double f_of_pair(int p) { return p == 0 ? 1.0 / 8 : 3.0 / 16; }

static int8_t s8(double v) { v = lrint(v * 127.999 - 0.5); if (v > 127) v = 127; if (v < -128) v = -128; return (int8_t)v; }

int main(int argc, char **argv)
{
	if (argc < 4) { fprintf(stderr, "usage: %s <uri> <txmask> <rxmask> [ampl]\n", argv[0]); return 2; }
	unsigned txm = strtoul(argv[2], NULL, 0), rxm = strtoul(argv[3], NULL, 0);
	double ampl = argc > 4 ? atof(argv[4]) : 0.5;

	struct iio_context *ctx = iio_create_context_from_uri(argv[1]);
	if (!ctx) { perror("contexte"); return 1; }
	iio_context_set_timeout(ctx, 10000);
	struct iio_device *phy = iio_context_find_device(ctx, "ad9361-phy");
	struct iio_device *txd = iio_context_find_device(ctx, "cf-ad9361-dds-core-lpc");
	struct iio_device *rxd = iio_context_find_device(ctx, "cf-ad9361-lpc");
	if (!phy || !txd || !rxd) { fprintf(stderr, "peripheriques introuvables\n"); return 1; }

	// horodatage coupe (timestamp_every = 0, interpolateur inactif), rebouclage numerique, 3,84 Mech/s
	// 0x80000000 : registre du coeur FPGA (sans ce bit, l acces part sur le SPI de l AD9363)
	iio_device_reg_write(rxd, 0x800000BC, 0);
	iio_device_reg_write(txd, 0x800000BC, 0);
	int r = iio_device_debug_attr_write(phy, "loopback", "1");
	if (r < 0) fprintf(stderr, "loopback : %d\n", r);
	struct iio_channel *c0 = iio_device_find_channel(phy, "voltage0", false);
	r = iio_channel_attr_write_longlong(c0, "sampling_frequency", 3840000);
	if (r < 0) fprintf(stderr, "sampling_frequency : %d\n", r);

	int ntx = iio_device_get_channels_count(txd), nrx = iio_device_get_channels_count(rxd);
	struct iio_channel *tc[4] = {0}, *rc[4] = {0};
	for (int k = 0; k < 4; k++) {
		char n[16]; snprintf(n, sizeof n, "voltage%d", k);
		tc[k] = iio_device_find_channel(txd, n, true);
		rc[k] = iio_device_find_channel(rxd, n, false);
	}
	(void)ntx; (void)nrx;
	for (int k = 0; k < 4; k++) {
		if (tc[k]) { if (txm & (1u << k)) iio_channel_enable(tc[k]); else iio_channel_disable(tc[k]); }
		else if (txm & (1u << k)) { fprintf(stderr, "TX voltage%d absent (mode 1r1t ?)\n", k); return 1; }
		if (rc[k]) { if (rxm & (1u << k)) iio_channel_enable(rc[k]); else iio_channel_disable(rc[k]); }
		else if (rxm & (1u << k)) { fprintf(stderr, "RX voltage%d absent (mode 1r1t ?)\n", k); return 1; }
	}

	struct iio_buffer *tb = iio_device_create_buffer(txd, NTX, true);
	if (!tb) { perror("tampon TX"); return 1; }
	ptrdiff_t ts = iio_buffer_step(tb);
	for (int p = 0; p < 2; p++) {
		int ei = (txm >> (2 * p)) & 1, eq = (txm >> (2 * p + 1)) & 1;
		if (!ei && !eq) continue;
		double f = f_of_pair(p);
		uint8_t *pi = iio_buffer_first(tb, tc[2 * p]), *pq = eq ? iio_buffer_first(tb, tc[2 * p + 1]) : NULL;
		for (int n = 0; n < NTX; n++) {
			double vi = ampl * cos(2 * M_PI * f * n), vq = ampl * sin(2 * M_PI * f * n);
			if (ei && !eq) {  // 8 bits
				uint16_t w = (uint16_t)((uint8_t)s8(vi) << 8 | (uint8_t)s8(vq));
				memcpy(pi + n * ts, &w, 2);
			} else {
				int16_t wi = (int16_t)lrint(vi * 32767), wq = (int16_t)lrint(vq * 32767);
				if (ei) memcpy(pi + n * ts, &wi, 2);
				memcpy(pq + n * ts, &wq, 2);
			}
		}
	}
	if (iio_buffer_push(tb) < 0) { perror("push TX"); return 1; }

	struct iio_buffer *rb = iio_device_create_buffer(rxd, NRX, false);
	if (!rb) { perror("tampon RX"); return 1; }
	for (int k = 0; k < 4; k++) if (iio_buffer_refill(rb) < 0) { perror("refill RX"); return 1; }
	ptrdiff_t rs = iio_buffer_step(rb);

	printf("TX masque 0x%x, RX masque 0x%x, amplitude %.2f\n", txm, rxm, ampl);
	for (int p = 0; p < 2; p++) {
		int ei = (rxm >> (2 * p)) & 1, eq = (rxm >> (2 * p + 1)) & 1;
		if (!ei) continue;
		uint8_t *pi = iio_buffer_first(rb, rc[2 * p]), *pq = eq ? iio_buffer_first(rb, rc[2 * p + 1]) : NULL;
		double complex acc[4] = {0};
		double pw = 0, si = 0, sq = 0;
		const double fr[4] = {1.0 / 8, -1.0 / 8, 3.0 / 16, -3.0 / 16};
		for (int n = 0; n < NRX; n++) {
			double i, q;
			if (eq) { int16_t a, b; memcpy(&a, pi + n * rs, 2); memcpy(&b, pq + n * rs, 2); i = a; q = b; }
			else { uint16_t w; memcpy(&w, pi + n * rs, 2); i = (int8_t)(w & 0xff) * 16.0; q = (int8_t)(w >> 8) * 16.0; }
			double complex x = i + I * q;
			for (int k = 0; k < 4; k++) acc[k] += x * cexp(-2 * M_PI * I * fr[k] * n);
			pw += i * i + q * q; si += i * i; sq += q * q;
		}
		{ // vidage pour analyse : /w/rx<voie>.c16 (I, Q en int16)
			char fn[32]; snprintf(fn, sizeof fn, "/w/rx%d.c16", p + 1);
			FILE *fo = fopen(fn, "wb");
			for (int n = 0; fo && n < NRX; n++) {
				int16_t v[2];
				if (eq) { memcpy(&v[0], pi + n * rs, 2); memcpy(&v[1], pq + n * rs, 2); }
				else { uint16_t w; memcpy(&w, pi + n * rs, 2); v[0] = (int8_t)(w & 0xff) * 16; v[1] = (int8_t)(w >> 8) * 16; }
				fwrite(v, 2, 2, fo);
			}
			if (fo) fclose(fo);
		}
		double ref = 2048 * 2048;  // pleine echelle 12 bits
		printf("RX%d (%s) : rms I %.0f Q %.0f | dBFS : +fs/8 %.1f, -fs/8 %.1f, +3fs/16 %.1f, -3fs/16 %.1f, total %.1f\n",
			   p + 1, eq ? "16 bits" : "8 bits", sqrt(si / NRX), sqrt(sq / NRX),
			   10 * log10(cabs(acc[0] / NRX) * cabs(acc[0] / NRX) / ref + 1e-15),
			   10 * log10(cabs(acc[1] / NRX) * cabs(acc[1] / NRX) / ref + 1e-15),
			   10 * log10(cabs(acc[2] / NRX) * cabs(acc[2] / NRX) / ref + 1e-15),
			   10 * log10(cabs(acc[3] / NRX) * cabs(acc[3] / NRX) / ref + 1e-15),
			   10 * log10(pw / NRX / ref + 1e-15));
	}
	iio_buffer_destroy(rb);
	iio_buffer_destroy(tb);
	iio_device_debug_attr_write(phy, "loopback", "0");
	iio_context_destroy(ctx);
	return 0;
}
