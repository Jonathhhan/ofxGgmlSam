#include "ofxGgmlSamExternalBackend.h"

#include "ofxGgmlSamUtils.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <utility>

namespace {
	ofxGgmlSamExternalAdapterSettings mergeSettings(
		const ofxGgmlSamExternalAdapterSettings & defaults,
		const ofxGgmlSamExternalAdapterSettings & requestSettings) {
		auto merged = defaults;
		if (!requestSettings.executablePath.empty()) {
			merged.executablePath = requestSettings.executablePath;
		}
		if (!requestSettings.workingDirectory.empty()) {
			merged.workingDirectory = requestSettings.workingDirectory;
		}
		if (!requestSettings.extraArguments.empty()) {
			merged.extraArguments = requestSettings.extraArguments;
		}
		if (!requestSettings.modelFlag.empty()) {
			merged.modelFlag = requestSettings.modelFlag;
		}
		if (!requestSettings.imageFlag.empty()) {
			merged.imageFlag = requestSettings.imageFlag;
		}
		if (!requestSettings.outputFlag.empty()) {
			merged.outputFlag = requestSettings.outputFlag;
		}
		if (!requestSettings.pointXFlag.empty()) {
			merged.pointXFlag = requestSettings.pointXFlag;
		}
		if (!requestSettings.pointYFlag.empty()) {
			merged.pointYFlag = requestSettings.pointYFlag;
		}
		if (!requestSettings.pointLabelFlag.empty()) {
			merged.pointLabelFlag = requestSettings.pointLabelFlag;
		}
		if (!requestSettings.boxX0Flag.empty()) {
			merged.boxX0Flag = requestSettings.boxX0Flag;
		}
		if (!requestSettings.boxY0Flag.empty()) {
			merged.boxY0Flag = requestSettings.boxY0Flag;
		}
		if (!requestSettings.boxX1Flag.empty()) {
			merged.boxX1Flag = requestSettings.boxX1Flag;
		}
		if (!requestSettings.boxY1Flag.empty()) {
			merged.boxY1Flag = requestSettings.boxY1Flag;
		}
		if (!requestSettings.boxLabelFlag.empty()) {
			merged.boxLabelFlag = requestSettings.boxLabelFlag;
		}
		if (!requestSettings.maskInputFlag.empty()) {
			merged.maskInputFlag = requestSettings.maskInputFlag;
		}
		return merged;
	}

	bool fileExists(const std::string & path) {
		return !path.empty() && std::filesystem::exists(std::filesystem::path(path));
	}

	std::string quoteShellArgument(const std::string & value) {
		std::string quoted = "\"";
		for (const auto c : value) {
			if (c == '"') {
				quoted += "\\\"";
			} else {
				quoted.push_back(c);
			}
		}
		quoted += "\"";
		return quoted;
	}

	void appendFlagValue(
		std::ostringstream & command,
		const std::string & flag,
		const std::string & value) {
		if (!flag.empty() && !value.empty()) {
			command << " " << quoteShellArgument(flag) << " " << quoteShellArgument(value);
		}
	}

	void appendFlagValue(
		std::ostringstream & command,
		const std::string & flag,
		float value) {
		if (!flag.empty()) {
			command << " " << quoteShellArgument(flag) << " " << value;
		}
	}

	std::filesystem::path makeTempPath(const std::string & suffix) {
		const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
		return std::filesystem::temp_directory_path() /
			("ofxGgmlSam-" + std::to_string(now) + suffix);
	}

	bool writePpmImage(
		const std::filesystem::path & path,
		const ofxGgmlSamImage & image,
		std::string & error) {
		if (image.channels < 1) {
			error = "SAM image has no channels";
			return false;
		}
		std::ofstream output(path, std::ios::binary);
		if (!output) {
			error = "could not write temporary SAM adapter image";
			return false;
		}
		output << "P6\n" << image.width << " " << image.height << "\n255\n";
		for (int y = 0; y < image.height; ++y) {
			for (int x = 0; x < image.width; ++x) {
				const auto base =
					(static_cast<std::size_t>(y) * static_cast<std::size_t>(image.width) +
						static_cast<std::size_t>(x)) *
					static_cast<std::size_t>(image.channels);
				const auto r = image.pixels[base];
				const auto g = image.channels > 1 ? image.pixels[base + 1] : r;
				const auto b = image.channels > 2 ? image.pixels[base + 2] : r;
				output.put(static_cast<char>(r));
				output.put(static_cast<char>(g));
				output.put(static_cast<char>(b));
			}
		}
		return static_cast<bool>(output);
	}

	bool writePgmMask(
		const std::filesystem::path & path,
		const ofxGgmlSamMask & mask,
		std::string & error) {
		if (!mask.isAllocated()) {
			error = "SAM refinement mask is not allocated";
			return false;
		}
		std::ofstream output(path, std::ios::binary);
		if (!output) {
			error = "could not write temporary SAM refinement mask";
			return false;
		}
		output << "P5\n" << mask.width << " " << mask.height << "\n255\n";
		for (const auto value : mask.values) {
			const auto byte = static_cast<unsigned char>(
				std::clamp(value, 0.0f, 1.0f) * 255.0f);
			output.put(static_cast<char>(byte));
		}
		return static_cast<bool>(output);
	}

	std::string readPnmToken(std::istream & input) {
		std::string token;
		char c = 0;
		while (input.get(c)) {
			if (std::isspace(static_cast<unsigned char>(c))) {
				continue;
			}
			if (c == '#') {
				std::string comment;
				std::getline(input, comment);
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

	bool loadPgmMask(
		const std::filesystem::path & path,
		ofxGgmlSamMask & mask,
		std::string & error) {
		std::ifstream input(path, std::ios::binary);
		if (!input) {
			error = "SAM adapter did not write a readable mask";
			return false;
		}
		const auto magic = readPnmToken(input);
		if (magic != "P5" && magic != "P2") {
			error = "SAM adapter mask must be a PGM file";
			return false;
		}
		const int width = std::stoi(readPnmToken(input));
		const int height = std::stoi(readPnmToken(input));
		const int maxValue = std::stoi(readPnmToken(input));
		if (width <= 0 || height <= 0 || maxValue <= 0) {
			error = "SAM adapter mask has invalid dimensions";
			return false;
		}
		mask.width = width;
		mask.height = height;
		mask.values.clear();
		mask.values.reserve(static_cast<std::size_t>(width) * static_cast<std::size_t>(height));
		if (magic == "P5") {
			for (int i = 0; i < width * height; ++i) {
				const auto byte = input.get();
				if (byte == EOF) {
					error = "SAM adapter mask ended early";
					return false;
				}
				mask.values.push_back(static_cast<float>(byte) / static_cast<float>(maxValue));
			}
		} else {
			for (int i = 0; i < width * height; ++i) {
				mask.values.push_back(
					static_cast<float>(std::stoi(readPnmToken(input))) /
					static_cast<float>(maxValue));
			}
		}
		mask.score = 1.0f;
		return mask.isAllocated();
	}

	std::string buildCommand(
		const ofxGgmlSamExternalAdapterSettings & settings,
		const ofxGgmlSamRequest & request,
		const std::filesystem::path & imagePath,
		const std::filesystem::path & outputPath,
		const std::filesystem::path & maskInputPath) {
		std::ostringstream command;
		if (!settings.workingDirectory.empty()) {
#if defined(_WIN32)
			command << "cd /d " << quoteShellArgument(settings.workingDirectory) << " && ";
#else
			command << "cd " << quoteShellArgument(settings.workingDirectory) << " && ";
#endif
		}
#if defined(_WIN32)
		command << "call ";
#endif
		command << quoteShellArgument(settings.executablePath);
		appendFlagValue(command, settings.modelFlag, request.modelPath);
		appendFlagValue(command, settings.imageFlag, imagePath.string());
		appendFlagValue(command, settings.outputFlag, outputPath.string());
		if (!maskInputPath.empty()) {
			appendFlagValue(command, settings.maskInputFlag, maskInputPath.string());
		}
		for (const auto & point : request.points) {
			appendFlagValue(command, settings.pointXFlag, point.x);
			appendFlagValue(command, settings.pointYFlag, point.y);
			appendFlagValue(
				command,
				settings.pointLabelFlag,
				point.positive ? "positive" : "negative");
		}
		for (const auto & box : request.boxes) {
			appendFlagValue(command, settings.boxX0Flag, box.x0);
			appendFlagValue(command, settings.boxY0Flag, box.y0);
			appendFlagValue(command, settings.boxX1Flag, box.x1);
			appendFlagValue(command, settings.boxY1Flag, box.y1);
			appendFlagValue(
				command,
				settings.boxLabelFlag,
				box.positive ? "positive" : "negative");
		}
		for (const auto & argument : settings.extraArguments) {
			if (!argument.empty()) {
				command << " " << quoteShellArgument(argument);
			}
		}
		return command.str();
	}
}

ofxGgmlSamExternalBackend::ofxGgmlSamExternalBackend(
	ofxGgmlSamExternalAdapterSettings settings)
	: settings(std::move(settings)) {
}

void ofxGgmlSamExternalBackend::setSettings(
	const ofxGgmlSamExternalAdapterSettings & settings) {
	this->settings = settings;
}

ofxGgmlSamExternalAdapterSettings ofxGgmlSamExternalBackend::getSettings() const {
	return settings;
}

bool ofxGgmlSamExternalBackend::isConfigured() const {
	return settings.isConfigured();
}

std::string ofxGgmlSamExternalBackend::getBackendName() const {
	return "external-sam";
}

ofxGgmlSamResult ofxGgmlSamExternalBackend::segment(
	const ofxGgmlSamRequest & request) const {
	const auto started = std::chrono::steady_clock::now();
	const auto mergedSettings = mergeSettings(settings, request.external);
	if (!mergedSettings.isConfigured()) {
		return ofxGgmlSamMakeError("external SAM executable is not configured");
	}
	if (!fileExists(mergedSettings.executablePath)) {
		return ofxGgmlSamMakeError("external SAM executable was not found: " + mergedSettings.executablePath);
	}
	if (!request.modelPath.empty() && !fileExists(request.modelPath)) {
		return ofxGgmlSamMakeError("SAM model was not found: " + request.modelPath);
	}

	std::string error;
	const auto imagePath = makeTempPath(".ppm");
	const auto maskInputPath = request.refinementMask.isAllocated()
		? makeTempPath(".input-mask.pgm")
		: std::filesystem::path();
	const auto maskPath = makeTempPath(".pgm");
	if (!writePpmImage(imagePath, request.image, error)) {
		return ofxGgmlSamMakeError(error);
	}
	if (!maskInputPath.empty() && !writePgmMask(maskInputPath, request.refinementMask, error)) {
		std::filesystem::remove(imagePath);
		return ofxGgmlSamMakeError(error);
	}
	const auto command = buildCommand(mergedSettings, request, imagePath, maskPath, maskInputPath);
	const auto exitCode = std::system(command.c_str());
	std::filesystem::remove(imagePath);
	if (!maskInputPath.empty()) {
		std::filesystem::remove(maskInputPath);
	}
	if (exitCode != 0) {
		std::filesystem::remove(maskPath);
		return ofxGgmlSamMakeError("external SAM executable failed with exit code " + std::to_string(exitCode));
	}

	ofxGgmlSamMask mask;
	if (!loadPgmMask(maskPath, mask, error)) {
		std::filesystem::remove(maskPath);
		return ofxGgmlSamMakeError(error);
	}
	std::filesystem::remove(maskPath);

	ofxGgmlSamResult result;
	result.success = true;
	result.backendName = getBackendName();
	result.imagePath = request.imagePath;
	result.elapsedMs = std::chrono::duration<float, std::milli>(
		std::chrono::steady_clock::now() - started).count();
	result.metadata.push_back({ "backend", getBackendName() });
	if (!request.modelPath.empty()) {
		result.metadata.push_back({ "modelPath", request.modelPath });
	}
	result.metadata.push_back({
		"refinementMask",
		request.refinementMask.isAllocated() ? "true" : "false"
	});
	result.masks.push_back(std::move(mask));
	return result;
}
