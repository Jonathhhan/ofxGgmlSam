#include "sam3.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cmath>
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
	float boxX0 = 0.25f;
	float boxY0 = 0.25f;
	float boxX1 = 0.75f;
	float boxY1 = 0.75f;
	bool useBox = false;
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

struct MaskStats {
	int width = 0;
	int height = 0;
	size_t activePixels = 0;
	double activeRatio = 0.0;
	double meanValue = 0.0;
	double promptValue = 0.0;
	double centerValue = 0.0;
	int boundsX = -1;
	int boundsY = -1;
	int boundsWidth = 0;
	int boundsHeight = 0;
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
		} else if (arg == "--box") {
			options.useBox = true;
		} else if (arg == "--box-x0") {
			options.boxX0 = parseFloat(requireValue(i, argc, argv, arg), arg);
			options.useBox = true;
		} else if (arg == "--box-y0") {
			options.boxY0 = parseFloat(requireValue(i, argc, argv, arg), arg);
			options.useBox = true;
		} else if (arg == "--box-x1") {
			options.boxX1 = parseFloat(requireValue(i, argc, argv, arg), arg);
			options.useBox = true;
		} else if (arg == "--box-y1") {
			options.boxY1 = parseFloat(requireValue(i, argc, argv, arg), arg);
			options.useBox = true;
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
				"usage: ofxGgmlSam3RuntimeSmoke --model path --backend cpu|cuda [--image fixture.ppm] [--box] [--json] [--summary-only]");
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
	options.boxX0 = std::clamp(options.boxX0, 0.0f, 1.0f);
	options.boxY0 = std::clamp(options.boxY0, 0.0f, 1.0f);
	options.boxX1 = std::clamp(options.boxX1, 0.0f, 1.0f);
	options.boxY1 = std::clamp(options.boxY1, 0.0f, 1.0f);
	if (options.boxX0 > options.boxX1) {
		std::swap(options.boxX0, options.boxX1);
	}
	if (options.boxY0 > options.boxY1) {
		std::swap(options.boxY0, options.boxY1);
	}
	if (options.useBox && (options.boxX0 == options.boxX1 || options.boxY0 == options.boxY1)) {
		throw std::runtime_error("box prompt must describe a positive-area rectangle");
	}
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

template <typename Value>
double normalizedMaskValue(Value value) {
	const double numericValue = static_cast<double>(value);
	const double normalized = numericValue > 1.0 ? numericValue / 255.0 : numericValue;
	return std::clamp(normalized, 0.0, 1.0);
}

template <typename Values>
MaskStats computeMaskStats(
	const Values & values,
	int width,
	int height,
	float pointX,
	float pointY) {
	MaskStats stats;
	stats.width = width;
	stats.height = height;
	if (width <= 0 || height <= 0 || values.empty()) {
		return stats;
	}

	const size_t expectedSize = static_cast<size_t>(width) * static_cast<size_t>(height);
	const size_t usableSize = std::min(expectedSize, values.size());
	const int promptX = std::clamp(
		static_cast<int>(std::round(pointX * static_cast<float>(width - 1))),
		0,
		std::max(0, width - 1));
	const int promptY = std::clamp(
		static_cast<int>(std::round(pointY * static_cast<float>(height - 1))),
		0,
		std::max(0, height - 1));
	const int centerX = std::max(0, width / 2);
	const int centerY = std::max(0, height / 2);

	int minX = width;
	int minY = height;
	int maxX = -1;
	int maxY = -1;
	double sum = 0.0;
	for (size_t i = 0; i < usableSize; ++i) {
		const double value = normalizedMaskValue(values[i]);
		sum += value;
		if (value > 0.5) {
			const int x = static_cast<int>(i % static_cast<size_t>(width));
			const int y = static_cast<int>(i / static_cast<size_t>(width));
			++stats.activePixels;
			minX = std::min(minX, x);
			minY = std::min(minY, y);
			maxX = std::max(maxX, x);
			maxY = std::max(maxY, y);
		}
	}

	stats.meanValue = sum / static_cast<double>(usableSize);
	stats.activeRatio = static_cast<double>(stats.activePixels) / static_cast<double>(usableSize);
	const size_t promptIndex =
		static_cast<size_t>(promptY) * static_cast<size_t>(width) + static_cast<size_t>(promptX);
	const size_t centerIndex =
		static_cast<size_t>(centerY) * static_cast<size_t>(width) + static_cast<size_t>(centerX);
	if (promptIndex < usableSize) {
		stats.promptValue = normalizedMaskValue(values[promptIndex]);
	}
	if (centerIndex < usableSize) {
		stats.centerValue = normalizedMaskValue(values[centerIndex]);
	}
	if (stats.activePixels > 0) {
		stats.boundsX = minX;
		stats.boundsY = minY;
		stats.boundsWidth = maxX - minX + 1;
		stats.boundsHeight = maxY - minY + 1;
	}
	return stats;
}

MaskStats computeFirstMaskStats(
	const sam3_result & result,
	float pointX,
	float pointY) {
	if (result.detections.empty()) {
		return {};
	}
	const auto & mask = result.detections.front().mask;
	return computeMaskStats(mask.data, mask.width, mask.height, pointX, pointY);
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
	const MaskStats firstMaskStats = passed
		? computeFirstMaskStats(result, options.pointX, options.pointY)
		: MaskStats {};
	std::cout << std::fixed << std::setprecision(3);
	std::cout << "{\n";
	std::cout << "  \"SummaryOnly\": " << (options.summaryOnly ? "true" : "false") << ",\n";
	std::cout << "  \"Summary\": {\n";
	std::cout << "    \"Passed\": " << (passed ? "true" : "false") << ",\n";
	std::cout << "    \"InferenceChecked\": " << (passed ? "true" : "false") << ",\n";
	std::cout << "    \"SmokeKind\": \"model-backed-sam3-point-segmentation\",\n";
	std::cout << "    \"PromptKind\": \"" << (options.useBox ? "box" : "point") << "\",\n";
	std::cout << "    \"Backend\": \"" << jsonEscape(options.backend) << "\",\n";
	std::cout << "    \"ModelPath\": \"" << jsonEscape(options.modelPath) << "\",\n";
	std::cout << "    \"ImagePath\": \"" << jsonEscape(options.imagePath) << "\",\n";
	std::cout << "    \"Threads\": " << options.threads << ",\n";
	std::cout << "    \"ImageSize\": " << options.imageSize << ",\n";
	std::cout << "    \"BoxPrompt\": " << (options.useBox ? "true" : "false") << ",\n";
	std::cout << "    \"BoxX0\": " << options.boxX0 << ",\n";
	std::cout << "    \"BoxY0\": " << options.boxY0 << ",\n";
	std::cout << "    \"BoxX1\": " << options.boxX1 << ",\n";
	std::cout << "    \"BoxY1\": " << options.boxY1 << ",\n";
	std::cout << "    \"MaskCount\": " << maskCount << ",\n";
	std::cout << "    \"FirstMaskWidth\": " << firstMaskStats.width << ",\n";
	std::cout << "    \"FirstMaskHeight\": " << firstMaskStats.height << ",\n";
	std::cout << "    \"FirstMaskActivePixels\": " << firstMaskStats.activePixels << ",\n";
	std::cout << "    \"FirstMaskActiveRatio\": " << firstMaskStats.activeRatio << ",\n";
	std::cout << "    \"FirstMaskMeanValue\": " << firstMaskStats.meanValue << ",\n";
	std::cout << "    \"FirstMaskPromptValue\": " << firstMaskStats.promptValue << ",\n";
	std::cout << "    \"FirstMaskCenterValue\": " << firstMaskStats.centerValue << ",\n";
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
			const MaskStats maskStats =
				computeMaskStats(mask.data, mask.width, mask.height, options.pointX, options.pointY);
			std::cout << "    {";
			std::cout << "\"Width\": " << mask.width << ", ";
			std::cout << "\"Height\": " << mask.height << ", ";
			std::cout << "\"IouScore\": " << mask.iou_score << ", ";
			std::cout << "\"ObjScore\": " << detection.score << ", ";
			std::cout << "\"ActivePixels\": " << maskStats.activePixels << ", ";
			std::cout << "\"ActiveRatio\": " << maskStats.activeRatio << ", ";
			std::cout << "\"MeanValue\": " << maskStats.meanValue << ", ";
			std::cout << "\"PromptValue\": " << maskStats.promptValue << ", ";
			std::cout << "\"CenterValue\": " << maskStats.centerValue << ", ";
			std::cout << "\"BoundsX\": " << maskStats.boundsX << ", ";
			std::cout << "\"BoundsY\": " << maskStats.boundsY << ", ";
			std::cout << "\"BoundsWidth\": " << maskStats.boundsWidth << ", ";
			std::cout << "\"BoundsHeight\": " << maskStats.boundsHeight;
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
		if (options.useBox) {
			pvs.use_box = true;
			pvs.box = {
				options.boxX0 * static_cast<float>(image.width),
				options.boxY0 * static_cast<float>(image.height),
				options.boxX1 * static_cast<float>(image.width),
				options.boxY1 * static_cast<float>(image.height)
			};
		} else {
			pvs.pos_points.push_back({
				options.pointX * static_cast<float>(image.width),
				options.pointY * static_cast<float>(image.height)
			});
		}

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
