#include "ofxGgmlSam/ofxGgmlSamExternalBackend.h"
#include "ofxGgmlSam/ofxGgmlSamInference.h"
#include "ofxGgmlSam/ofxGgmlSamUtils.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
struct Options {
	std::string adapterPath;
	std::string modelPath;
	std::filesystem::path outputDir;
	std::vector<std::filesystem::path> inputs;
	std::vector<std::filesystem::path> inputDirs;
	ofxGgmlSamPoint point = ofxGgmlSamMakePoint(0.5f, 0.5f, true);
	std::vector<ofxGgmlSamBox> boxes;
	ofxGgmlSamBox pendingBox;
	bool hasBoxX0 = false;
	bool hasBoxY0 = false;
	bool hasBoxX1 = false;
	bool hasBoxY1 = false;
	bool hasAnyBoxFlag = false;
	bool json = false;
	bool summaryOnly = false;
};

std::string readPnmToken(std::istream & input) {
	std::string token;
	char c = 0;
	while (input.get(c)) {
		if (std::isspace(static_cast<unsigned char>(c))) {
			continue;
		}
		if (c == '#') {
			std::string ignored;
			std::getline(input, ignored);
			continue;
		}
		token.push_back(c);
		break;
	}
	while (input.get(c)) {
		if (std::isspace(static_cast<unsigned char>(c))) {
			break;
		}
		token.push_back(c);
	}
	return token;
}

bool loadPpmImage(
	const std::filesystem::path & path,
	ofxGgmlSamImage & image,
	std::string & error) {
	std::ifstream input(path, std::ios::binary);
	if (!input) {
		error = "could not open input image";
		return false;
	}
	const auto magic = readPnmToken(input);
	if (magic != "P6" && magic != "P3") {
		error = "batch input images must be PPM P6 or P3";
		return false;
	}
	const int width = std::stoi(readPnmToken(input));
	const int height = std::stoi(readPnmToken(input));
	const int maxValue = std::stoi(readPnmToken(input));
	if (width <= 0 || height <= 0 || maxValue <= 0 || maxValue > 255) {
		error = "PPM image has invalid dimensions or max value";
		return false;
	}
	image.width = width;
	image.height = height;
	image.channels = 3;
	image.pixels.clear();
	image.pixels.reserve(
		static_cast<std::size_t>(width) *
		static_cast<std::size_t>(height) *
		static_cast<std::size_t>(image.channels));
	const auto count =
		static_cast<std::size_t>(width) *
		static_cast<std::size_t>(height) *
		static_cast<std::size_t>(image.channels);
	if (magic == "P6") {
		image.pixels.resize(count);
		input.read(reinterpret_cast<char *>(image.pixels.data()),
			static_cast<std::streamsize>(image.pixels.size()));
		if (input.gcount() != static_cast<std::streamsize>(image.pixels.size())) {
			error = "PPM image pixel data was truncated";
			return false;
		}
		return true;
	}
	for (std::size_t i = 0; i < count; ++i) {
		const auto token = readPnmToken(input);
		if (token.empty()) {
			error = "PPM image pixel data was truncated";
			return false;
		}
		image.pixels.push_back(static_cast<std::uint8_t>(std::stoi(token)));
	}
	return true;
}

bool writePgmMask(
	const std::filesystem::path & path,
	const ofxGgmlSamMask & mask,
	std::string & error) {
	if (!mask.isAllocated()) {
		error = "result mask was not allocated";
		return false;
	}
	std::ofstream output(path, std::ios::binary);
	if (!output) {
		error = "could not write output mask";
		return false;
	}
	output << "P5\n" << mask.width << " " << mask.height << "\n255\n";
	for (const auto value : mask.values) {
		const auto clamped = std::max(0.0f, std::min(1.0f, value));
		output.put(static_cast<char>(static_cast<unsigned char>(clamped * 255.0f)));
	}
	return static_cast<bool>(output);
}

std::string jsonEscape(const std::string & value) {
	std::ostringstream out;
	for (const auto c : value) {
		switch (c) {
		case '\\':
			out << "\\\\";
			break;
		case '"':
			out << "\\\"";
			break;
		case '\n':
			out << "\\n";
			break;
		case '\r':
			out << "\\r";
			break;
		case '\t':
			out << "\\t";
			break;
		default:
			out << c;
			break;
		}
	}
	return out.str();
}

std::string toLower(std::string value) {
	std::transform(value.begin(), value.end(), value.begin(),
		[](unsigned char c) { return static_cast<char>(std::tolower(c)); });
	return value;
}

bool isPpmPath(const std::filesystem::path & path) {
	const auto extension = toLower(path.extension().string());
	return extension == ".ppm" || extension == ".pnm";
}

void collectInputDir(
	const std::filesystem::path & dir,
	std::vector<std::filesystem::path> & inputs) {
	for (const auto & entry : std::filesystem::directory_iterator(dir)) {
		if (entry.is_regular_file() && isPpmPath(entry.path())) {
			inputs.push_back(entry.path());
		}
	}
}

std::filesystem::path makeMaskPath(
	const std::filesystem::path & outputDir,
	std::size_t index,
	const std::filesystem::path & inputPath) {
	std::ostringstream name;
	name << index << "-" << inputPath.stem().string() << "-mask-0.pgm";
	return outputDir / name.str();
}

void printUsage() {
	std::cerr
		<< "usage: ofxGgmlSamBatchExternal --adapter runner --output-dir masks "
		<< "[--input image.ppm ...] [--input-dir images]\n"
		<< "       [--model model] [--point-x 0.5 --point-y 0.5 "
		<< "--point-label positive] [--box-x0 ... --box-y0 ... --box-x1 ... --box-y1 ...]\n";
}

bool parseOptions(int argc, char ** argv, Options & options) {
	for (int i = 1; i < argc; ++i) {
		const std::string arg = argv[i];
		auto nextValue = [&](const std::string & flag) -> std::string {
			if (i + 1 >= argc) {
				throw std::runtime_error("missing value for " + flag);
			}
			return argv[++i];
		};
		if (arg == "--adapter") {
			options.adapterPath = nextValue(arg);
		} else if (arg == "--model") {
			options.modelPath = nextValue(arg);
		} else if (arg == "--output-dir") {
			options.outputDir = nextValue(arg);
		} else if (arg == "--input") {
			options.inputs.push_back(nextValue(arg));
		} else if (arg == "--input-dir") {
			options.inputDirs.push_back(nextValue(arg));
		} else if (arg == "--point-x") {
			options.point.x = std::stof(nextValue(arg));
		} else if (arg == "--point-y") {
			options.point.y = std::stof(nextValue(arg));
		} else if (arg == "--point-label") {
			options.point.positive = nextValue(arg) != "negative";
		} else if (arg == "--box-x0") {
			options.pendingBox.x0 = std::stof(nextValue(arg));
			options.hasBoxX0 = true;
			options.hasAnyBoxFlag = true;
		} else if (arg == "--box-y0") {
			options.pendingBox.y0 = std::stof(nextValue(arg));
			options.hasBoxY0 = true;
			options.hasAnyBoxFlag = true;
		} else if (arg == "--box-x1") {
			options.pendingBox.x1 = std::stof(nextValue(arg));
			options.hasBoxX1 = true;
			options.hasAnyBoxFlag = true;
		} else if (arg == "--box-y1") {
			options.pendingBox.y1 = std::stof(nextValue(arg));
			options.hasBoxY1 = true;
			options.hasAnyBoxFlag = true;
		} else if (arg == "--box-label") {
			options.pendingBox.positive = nextValue(arg) != "negative";
			options.hasAnyBoxFlag = true;
		} else if (arg == "--json") {
			options.json = true;
		} else if (arg == "--summary-only") {
			options.summaryOnly = true;
		} else if (arg == "--help" || arg == "-h") {
			printUsage();
			std::exit(EXIT_SUCCESS);
		} else {
			throw std::runtime_error("unknown argument: " + arg);
		}
	}
	if (options.hasAnyBoxFlag) {
		if (!options.hasBoxX0 || !options.hasBoxY0 ||
			!options.hasBoxX1 || !options.hasBoxY1) {
			throw std::runtime_error("box prompts require --box-x0, --box-y0, --box-x1, and --box-y1");
		}
		options.boxes.push_back(options.pendingBox);
	}
	return true;
}

void printJsonSummary(
	const std::vector<std::filesystem::path> & inputs,
	const std::vector<ofxGgmlSamResult> & results,
	const std::vector<std::filesystem::path> & maskPaths) {
	std::cout << "{\n";
	std::cout << "  \"name\": \"ofxGgmlSam external batch\",\n";
	std::cout << "  \"count\": " << results.size() << ",\n";
	std::cout << "  \"items\": [\n";
	for (std::size_t i = 0; i < results.size(); ++i) {
		const auto & result = results[i];
		std::cout << "    {\n";
		std::cout << "      \"input\": \"" << jsonEscape(inputs[i].string()) << "\",\n";
		std::cout << "      \"success\": " << (result.isOk() ? "true" : "false") << ",\n";
		std::cout << "      \"maskCount\": " << result.masks.size();
		if (result.isOk() && !maskPaths[i].empty()) {
			std::cout << ",\n      \"maskPath\": \"" << jsonEscape(maskPaths[i].string()) << "\"";
		}
		if (result.isError()) {
			std::cout << ",\n      \"error\": \"" << jsonEscape(result.errorMessage) << "\"";
		}
		std::cout << "\n    }" << (i + 1 < results.size() ? "," : "") << "\n";
	}
	std::cout << "  ]\n";
	std::cout << "}\n";
}
}

int main(int argc, char ** argv) {
	Options options;
	try {
		parseOptions(argc, argv, options);
		for (const auto & dir : options.inputDirs) {
			collectInputDir(dir, options.inputs);
		}
		std::sort(options.inputs.begin(), options.inputs.end());
		if (options.adapterPath.empty()) {
			throw std::runtime_error("--adapter is required");
		}
		if (options.outputDir.empty()) {
			throw std::runtime_error("--output-dir is required");
		}
		if (options.inputs.empty()) {
			throw std::runtime_error("at least one --input or --input-dir image is required");
		}
		std::filesystem::create_directories(options.outputDir);
	} catch (const std::exception & exception) {
		std::cerr << "error: " << exception.what() << "\n";
		printUsage();
		return EXIT_FAILURE;
	}

	std::vector<ofxGgmlSamRequest> requests;
	requests.reserve(options.inputs.size());
	for (const auto & inputPath : options.inputs) {
		ofxGgmlSamRequest request;
		request.modelPath = options.modelPath;
		request.imagePath = inputPath.string();
		request.points.push_back(options.point);
		request.boxes = options.boxes;
		request.external.executablePath = options.adapterPath;
		std::string error;
		if (!loadPpmImage(inputPath, request.image, error)) {
			auto result = ofxGgmlSamMakeError(inputPath.string() + ": " + error);
			result.imagePath = inputPath.string();
			requests.push_back(request);
			continue;
		}
		requests.push_back(request);
	}

	ofxGgmlSamInference inference;
	inference.setBackend(std::make_shared<ofxGgmlSamExternalBackend>());
	auto results = inference.segmentBatch(requests);
	std::vector<std::filesystem::path> maskPaths(results.size());
	bool allOk = true;
	for (std::size_t i = 0; i < results.size(); ++i) {
		auto & result = results[i];
		if (result.isError()) {
			allOk = false;
			continue;
		}
		if (result.masks.empty()) {
			result = ofxGgmlSamMakeError("batch item returned no masks");
			allOk = false;
			continue;
		}
		if (options.summaryOnly) {
			continue;
		}
		std::string error;
		const auto maskPath = makeMaskPath(options.outputDir, i, options.inputs[i]);
		if (!writePgmMask(maskPath, result.masks.front(), error)) {
			result = ofxGgmlSamMakeError(error);
			allOk = false;
			continue;
		}
		maskPaths[i] = maskPath;
	}

	if (options.json) {
		printJsonSummary(options.inputs, results, maskPaths);
	} else {
		std::cout << "Processed " << results.size() << " image(s)\n";
		for (std::size_t i = 0; i < results.size(); ++i) {
			std::cout << (results[i].isOk() ? "OK " : "ERR ")
				<< options.inputs[i].string();
			if (!maskPaths[i].empty()) {
				std::cout << " -> " << maskPaths[i].string();
			}
			if (results[i].isError()) {
				std::cout << " :: " << results[i].errorMessage;
			}
			std::cout << "\n";
		}
	}
	return allOk ? EXIT_SUCCESS : EXIT_FAILURE;
}
