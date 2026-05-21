#include "sam3.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <io.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

namespace {

struct Options {
	std::string modelPath;
	std::string imagePath;
	std::string backend = "cpu";
	int threads = 0;
	int imageSize = 256;
	float pointX = 0.5f;
	float pointY = 0.5f;
	bool multimask = false;
	bool json = false;
	bool summaryOnly = false;
};

struct Timings {
	double loadMs = 0.0;
	double stateMs = 0.0;
	double encodeMs = 0.0;
	double segmentMs = 0.0;
	double totalMs = 0.0;
};

class StdoutSilencer {
public:
	void start() {
		if (active) {
			return;
		}
		std::fflush(stdout);
#if defined(_WIN32)
		savedFd = _dup(_fileno(stdout));
		if (savedFd >= 0) {
			std::freopen("NUL", "w", stdout);
			active = true;
		}
#else
		savedFd = dup(fileno(stdout));
		const int nullFd = open("/dev/null", O_WRONLY);
		if (savedFd >= 0 && nullFd >= 0) {
			dup2(nullFd, fileno(stdout));
			close(nullFd);
			active = true;
		} else if (nullFd >= 0) {
			close(nullFd);
		}
#endif
	}

	void stop() {
		if (!active) {
			return;
		}
		std::fflush(stdout);
#if defined(_WIN32)
		_dup2(savedFd, _fileno(stdout));
		_close(savedFd);
#else
		dup2(savedFd, fileno(stdout));
		close(savedFd);
#endif
		savedFd = -1;
		active = false;
		clearerr(stdout);
		std::cout.clear();
	}

	~StdoutSilencer() {
		stop();
	}

private:
	int savedFd = -1;
	bool active = false;
};

using Clock = std::chrono::steady_clock;

double elapsedMs(const Clock::time_point & start, const Clock::time_point & end) {
	return std::chrono::duration<double, std::milli>(end - start).count();
}

std::string lower(std::string value) {
	std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
		return static_cast<char>(std::tolower(c));
	});
	return value;
}

int parseInt(const std::string & value, const std::string & name) {
	char * end = nullptr;
	const long parsed = std::strtol(value.c_str(), &end, 10);
	if (!end || *end != '\0') {
		throw std::runtime_error("invalid integer for " + name + ": " + value);
	}
	return static_cast<int>(parsed);
}

float parseFloat(const std::string & value, const std::string & name) {
	char * end = nullptr;
	const float parsed = std::strtof(value.c_str(), &end);
	if (!end || *end != '\0') {
		throw std::runtime_error("invalid float for " + name + ": " + value);
	}
	return parsed;
}

std::string requireValue(int & index, int argc, char ** argv, const std::string & name) {
	if (index + 1 >= argc) {
		throw std::runtime_error("missing value for " + name);
	}
	++index;
	return argv[index];
}

Options parseOptions(int argc, char ** argv) {
	Options options;
	for (int i = 1; i < argc; ++i) {
		const std::string arg = argv[i];
		if (arg == "--model") {
			options.modelPath = requireValue(i, argc, argv, arg);
		} else if (arg == "--image") {
			options.imagePath = requireValue(i, argc, argv, arg);
		} else if (arg == "--backend") {
			options.backend = lower(requireValue(i, argc, argv, arg));
		} else if (arg == "--threads") {
			options.threads = parseInt(requireValue(i, argc, argv, arg), arg);
		} else if (arg == "--image-size") {
			options.imageSize = parseInt(requireValue(i, argc, argv, arg), arg);
		} else if (arg == "--point-x") {
			options.pointX = parseFloat(requireValue(i, argc, argv, arg), arg);
		} else if (arg == "--point-y") {
			options.pointY = parseFloat(requireValue(i, argc, argv, arg), arg);
		} else if (arg == "--multimask") {
			options.multimask = true;
		} else if (arg == "--json") {
			options.json = true;
		} else if (arg == "--summary-only") {
			options.summaryOnly = true;
		} else if (arg == "--use-gpu") {
			options.backend = "cuda";
		} else if (arg == "--help" || arg == "-h") {
			throw std::runtime_error(
				"usage: ofxGgmlSam3RuntimeSmoke --model path --backend cpu|cuda [--image fixture.ppm] [--json] [--summary-only]");
		} else {
			throw std::runtime_error("unknown argument: " + arg);
		}
	}
	if (options.modelPath.empty()) {
		throw std::runtime_error("--model is required");
	}
	if (options.backend != "cpu" && options.backend != "cuda") {
		throw std::runtime_error("--backend must be cpu or cuda");
	}
	if (options.imageSize < 32) {
		throw std::runtime_error("--image-size must be at least 32");
	}
	options.pointX = std::clamp(options.pointX, 0.0f, 1.0f);
	options.pointY = std::clamp(options.pointY, 0.0f, 1.0f);
	return options;
}

std::string readPpmToken(std::istream & input) {
	std::string token;
	while (input >> token) {
		if (!token.empty() && token[0] == '#') {
			std::string ignored;
			std::getline(input, ignored);
			continue;
		}
		return token;
	}
	return "";
}

uint8_t scalePpmSample(int sample, int maxValue) {
	if (maxValue <= 0) {
		throw std::runtime_error("PPM max value must be positive");
	}
	const int clamped = std::clamp(sample, 0, maxValue);
	return static_cast<uint8_t>((clamped * 255 + (maxValue / 2)) / maxValue);
}

sam3_image loadPpmImage(const std::string & path) {
	std::ifstream input(path, std::ios::binary);
	if (!input) {
		throw std::runtime_error("could not open fixture image: " + path);
	}

	const std::string magic = readPpmToken(input);
	if (magic != "P3" && magic != "P6") {
		throw std::runtime_error("fixture image must be an RGB PPM file");
	}
	const int width = parseInt(readPpmToken(input), "PPM width");
	const int height = parseInt(readPpmToken(input), "PPM height");
	const int maxValue = parseInt(readPpmToken(input), "PPM max value");
	if (width <= 0 || height <= 0) {
		throw std::runtime_error("fixture image dimensions must be positive");
	}

	sam3_image image;
	image.width = width;
	image.height = height;
	image.channels = 3;
	image.data.resize(static_cast<size_t>(width) * static_cast<size_t>(height) * 3u);

	if (magic == "P3") {
		for (auto & value : image.data) {
			const std::string sampleToken = readPpmToken(input);
			if (sampleToken.empty()) {
				throw std::runtime_error("fixture image ended before all PPM samples were read");
			}
			value = scalePpmSample(parseInt(sampleToken, "PPM sample"), maxValue);
		}
		return image;
	}

	const int separator = input.get();
	if (separator == '\r' && input.peek() == '\n') {
		input.get();
	} else if (separator != '\n' && separator != '\t' && separator != ' ') {
		throw std::runtime_error("PPM header was not followed by pixel data");
	}
	for (auto & value : image.data) {
		const int sample = input.get();
		if (sample == EOF) {
			throw std::runtime_error("fixture image ended before all PPM bytes were read");
		}
		value = scalePpmSample(sample, maxValue);
	}
	return image;
}

sam3_image makeSyntheticImage(int size) {
	sam3_image image;
	image.width = size;
	image.height = size;
	image.channels = 3;
	image.data.resize(static_cast<size_t>(size) * static_cast<size_t>(size) * 3u);
	for (int y = 0; y < size; ++y) {
		for (int x = 0; x < size; ++x) {
			const bool inside =
				x > size / 4 && x < (size * 3) / 4 &&
				y > size / 4 && y < (size * 3) / 4;
			const size_t base =
				(static_cast<size_t>(y) * static_cast<size_t>(size) +
					static_cast<size_t>(x)) *
				3u;
			image.data[base + 0] = inside ? 235 : static_cast<uint8_t>((x * 255) / std::max(1, size - 1));
			image.data[base + 1] = inside ? 65 : static_cast<uint8_t>((y * 255) / std::max(1, size - 1));
			image.data[base + 2] = inside ? 85 : 48;
		}
	}
	return image;
}

std::string jsonEscape(const std::string & value) {
	std::ostringstream out;
	for (const char c : value) {
		switch (c) {
			case '\\': out << "\\\\"; break;
			case '"': out << "\\\""; break;
			case '\n': out << "\\n"; break;
			case '\r': out << "\\r"; break;
			case '\t': out << "\\t"; break;
			default: out << c; break;
		}
	}
	return out.str();
}

void writeTextSummary(
	const Options & options,
	const Timings & timings,
	const sam3_result & result) {
	std::cout << "ofxGgmlSam SAM3 runtime smoke\n";
	std::cout << "Passed:    true\n";
	std::cout << "Backend:   " << options.backend << "\n";
	std::cout << "Model:     " << options.modelPath << "\n";
	if (options.imagePath.empty()) {
		std::cout << "Image:     " << options.imageSize << "x" << options.imageSize << " synthetic RGB\n";
	} else {
		std::cout << "Image:     " << options.imagePath << "\n";
	}
	std::cout << "Masks:     " << result.detections.size() << "\n";
	std::cout << std::fixed << std::setprecision(1);
	std::cout << "LoadMs:    " << timings.loadMs << "\n";
	std::cout << "StateMs:   " << timings.stateMs << "\n";
	std::cout << "EncodeMs:  " << timings.encodeMs << "\n";
	std::cout << "SegmentMs: " << timings.segmentMs << "\n";
	std::cout << "TotalMs:   " << timings.totalMs << "\n";
}

void writeJson(
	const Options & options,
	const Timings & timings,
	const sam3_result & result,
	const std::string & error = "") {
	const bool passed = error.empty();
	const size_t maskCount = passed ? result.detections.size() : 0u;
	std::cout << std::fixed << std::setprecision(3);
	std::cout << "{\n";
	std::cout << "  \"SummaryOnly\": " << (options.summaryOnly ? "true" : "false") << ",\n";
	std::cout << "  \"Summary\": {\n";
	std::cout << "    \"Passed\": " << (passed ? "true" : "false") << ",\n";
	std::cout << "    \"InferenceChecked\": " << (passed ? "true" : "false") << ",\n";
	std::cout << "    \"SmokeKind\": \"model-backed-sam3-point-segmentation\",\n";
	std::cout << "    \"Backend\": \"" << jsonEscape(options.backend) << "\",\n";
	std::cout << "    \"ModelPath\": \"" << jsonEscape(options.modelPath) << "\",\n";
	std::cout << "    \"ImagePath\": \"" << jsonEscape(options.imagePath) << "\",\n";
	std::cout << "    \"Threads\": " << options.threads << ",\n";
	std::cout << "    \"ImageSize\": " << options.imageSize << ",\n";
	std::cout << "    \"MaskCount\": " << maskCount << ",\n";
	std::cout << "    \"LoadMs\": " << timings.loadMs << ",\n";
	std::cout << "    \"StateMs\": " << timings.stateMs << ",\n";
	std::cout << "    \"EncodeMs\": " << timings.encodeMs << ",\n";
	std::cout << "    \"SegmentMs\": " << timings.segmentMs << ",\n";
	std::cout << "    \"TotalMs\": " << timings.totalMs << ",\n";
	std::cout << "    \"Error\": \"" << jsonEscape(error) << "\"\n";
	std::cout << "  }";
	if (!options.summaryOnly && passed) {
		std::cout << ",\n  \"Masks\": [\n";
		for (size_t i = 0; i < result.detections.size(); ++i) {
			const auto & detection = result.detections[i];
			const auto & mask = detection.mask;
			std::cout << "    {";
			std::cout << "\"Width\": " << mask.width << ", ";
			std::cout << "\"Height\": " << mask.height << ", ";
			std::cout << "\"IouScore\": " << mask.iou_score << ", ";
			std::cout << "\"ObjScore\": " << detection.score;
			std::cout << "}";
			if (i + 1 < result.detections.size()) {
				std::cout << ",";
			}
			std::cout << "\n";
		}
		std::cout << "  ]\n";
	} else {
		std::cout << "\n";
	}
	std::cout << "}\n";
}

} // namespace

int main(int argc, char ** argv) {
	Options options;
	Timings timings;
	sam3_result result;
	StdoutSilencer stdoutSilencer;

	try {
		options = parseOptions(argc, argv);
		options.threads = options.threads > 0 ? options.threads : 4;
		if (options.json) {
			stdoutSilencer.start();
		}

		const auto totalStart = Clock::now();
		sam3_params params;
		params.model_path = options.modelPath;
		params.n_threads = options.threads;
		params.use_gpu = options.backend == "cuda";
		params.seed = 42;

		const auto loadStart = Clock::now();
		auto model = sam3_load_model(params);
		const auto loadEnd = Clock::now();
		timings.loadMs = elapsedMs(loadStart, loadEnd);
		if (!model) {
			throw std::runtime_error("sam3_load_model returned null");
		}

		const auto stateStart = Clock::now();
		auto state = sam3_create_state(*model, params);
		const auto stateEnd = Clock::now();
		timings.stateMs = elapsedMs(stateStart, stateEnd);
		if (!state) {
			throw std::runtime_error("sam3_create_state returned null");
		}

		auto image = options.imagePath.empty()
			? makeSyntheticImage(options.imageSize)
			: loadPpmImage(options.imagePath);
		const auto encodeStart = Clock::now();
		if (!sam3_encode_image(*state, *model, image)) {
			throw std::runtime_error("sam3_encode_image failed");
		}
		const auto encodeEnd = Clock::now();
		timings.encodeMs = elapsedMs(encodeStart, encodeEnd);

		sam3_pvs_params pvs;
		pvs.multimask = options.multimask;
		pvs.pos_points.push_back({
			options.pointX * static_cast<float>(image.width),
			options.pointY * static_cast<float>(image.height)
		});

		const auto segmentStart = Clock::now();
		result = sam3_segment_pvs(*state, *model, pvs);
		const auto segmentEnd = Clock::now();
		timings.segmentMs = elapsedMs(segmentStart, segmentEnd);
		timings.totalMs = elapsedMs(totalStart, Clock::now());

		if (result.detections.empty()) {
			throw std::runtime_error("sam3_segment_pvs produced no detections");
		}

		if (options.json) {
			stdoutSilencer.stop();
			writeJson(options, timings, result);
		} else {
			writeTextSummary(options, timings, result);
		}
		return 0;
	} catch (const std::exception & exception) {
		timings.totalMs = timings.totalMs > 0.0 ? timings.totalMs : elapsedMs(Clock::now(), Clock::now());
		if (options.json) {
			stdoutSilencer.stop();
			writeJson(options, timings, result, exception.what());
		} else {
			std::cerr << "ofxGgmlSam SAM3 runtime smoke failed: " << exception.what() << "\n";
		}
		return 1;
	}
}
