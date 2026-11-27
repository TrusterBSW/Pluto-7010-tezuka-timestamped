// Essai de l'emission 8 bits (ip_cs8=1) par rebouclage numerique AD9363 (loopback=1).
// TX : tonalite complexe exp(+j 2 pi n/8) ; RX en 16 bits (sans ip_cs8) pour isoler le TX.
// Mesures : puissance de la raie +fs/8 et de son image -fs/8, rms I et Q recus, correlation I/Q.
// Usage : cs8loop <device_args> <tx_cs8 0|1> [amplitude 0..1] [rx_cs8 0|1]
#include <SoapySDR/Device.hpp>
#include <SoapySDR/Formats.hpp>
#include <atomic>
#include <cmath>
#include <complex>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>

int main(int argc, char **argv)
{
	if (argc < 3) { fprintf(stderr, "usage: %s <args> <tx_cs8 0|1> [ampl]\n", argv[0]); return 2; }
	const bool cs8 = atoi(argv[2]) != 0;
	const double ampl = argc > 3 ? atof(argv[3]) : 0.5;
	const bool rxcs8 = argc > 4 && atoi(argv[4]) != 0;
	const double fs = 3.84e6;

	SoapySDR::Device *dev = SoapySDR::Device::make(argv[1]);
	dev->setSampleRate(SOAPY_SDR_RX, 0, fs);
	dev->setSampleRate(SOAPY_SDR_TX, 0, fs);

	SoapySDR::Kwargs txa;
	if (cs8) txa["ip_cs8"] = "1";
	SoapySDR::Kwargs rxa;
	if (rxcs8) rxa["ip_cs8"] = "1";
	SoapySDR::Stream *rx = dev->setupStream(SOAPY_SDR_RX, SOAPY_SDR_CS16, {0}, rxa);
	SoapySDR::Stream *tx = dev->setupStream(SOAPY_SDR_TX, SOAPY_SDR_CS16, {0}, txa);
	const size_t mtu = dev->getStreamMTU(tx);

	// tonalite +fs/8, periode 8 echantillons
	std::vector<int16_t> buf(2 * mtu);
	for (size_t n = 0; n < mtu; n++) {
		buf[2 * n] = int16_t(lrint(ampl * 32767 * cos(2 * M_PI * n / 8)));
		buf[2 * n + 1] = int16_t(lrint(ampl * 32767 * sin(2 * M_PI * n / 8)));
	}
	dev->activateStream(tx);
	dev->activateStream(rx);

	std::atomic<bool> run{true};
	std::thread t([&] {
		const void *b[1] = {buf.data()};
		while (run) {
			int flags = 0;
			int r = dev->writeStream(tx, b, mtu - (mtu % 8), flags, 0, 100000);
			if (r < 0 && r != SOAPY_SDR_TIMEOUT) { fprintf(stderr, "writeStream %d\n", r); }
		}
	});

	// laisser le TX s'etablir, puis lire
	std::vector<int16_t> rb(2 * 65536);
	size_t got = 0;
	auto t0 = std::chrono::steady_clock::now();
	while (std::chrono::steady_clock::now() - t0 < std::chrono::milliseconds(1500)) {
		void *b[1] = {rb.data()};
		int flags; long long tns;
		dev->readStream(rx, b, 65536 / 4, flags, tns, 100000);
	}
	auto t1 = std::chrono::steady_clock::now();
	while (got < 65536) {
		if (std::chrono::steady_clock::now() - t1 > std::chrono::seconds(10)) { fprintf(stderr, "RX : %zu echantillons en 10 s, abandon\n", got); break; }
		void *b[1] = {rb.data() + 2 * got};
		int flags; long long tns;
		int r = dev->readStream(rx, b, 65536 - got, flags, tns, 100000);
		if (r > 0) got += r; else if (r != SOAPY_SDR_TIMEOUT) fprintf(stderr, "readStream %d\n", r);
	}
	run = false; t.join();
	dev->deactivateStream(rx); dev->deactivateStream(tx);
	dev->closeStream(rx); dev->closeStream(tx);
	SoapySDR::Device::unmake(dev);

	// analyse
	std::complex<double> pp = 0, pm = 0, dc = 0;
	double si = 0, sq = 0, siq = 0;
	for (size_t n = 0; n < got; n++) {
		double i = rb[2 * n], q = rb[2 * n + 1];
		std::complex<double> x(i, q), e = std::polar(1.0, -2 * M_PI * double(n % 8) / 8);
		pp += x * e; pm += x * std::conj(e); dc += x;
		si += i * i; sq += q * q; siq += i * q;
	}
	double N = got;
	double Pp = std::norm(pp / N), Pm = std::norm(pm / N), Ptot = (si + sq) / N;
	printf("tx_cs8=%d rx_cs8=%d ampl=%.2f N=%zu\n", cs8, rxcs8, ampl, got);
	printf("rms I=%.1f Q=%.1f  (LSB 12 bits sur 16)\n", sqrt(si / N), sqrt(sq / N));
	printf("raie +fs/8 : %.1f dB ; image -fs/8 : %.1f dB ; rejection image : %.1f dB\n",
		   10 * log10(Pp + 1e-12), 10 * log10(Pm + 1e-12), 10 * log10((Pp + 1e-12) / (Pm + 1e-12)));
	printf("residu (hors +/-f et DC) : %.1f dB sous la raie\n",
		   10 * log10(Pp / std::max(1e-12, Ptot - Pp - Pm - std::norm(dc / N))));
	printf("premiers echantillons :");
	for (int n = 0; n < 8; n++) printf(" (%d,%d)", rb[2 * n], rb[2 * n + 1]);
	printf("\n");
	return 0;
}
