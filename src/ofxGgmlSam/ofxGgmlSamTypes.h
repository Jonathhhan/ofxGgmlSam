#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

struct ofxGgmlSamPoint {
	float x = 0.0f;
	float y = 0.0f;
	bool positive = true;
};

struct ofxGgmlSamExternalAdapterSettings {
	std::string executablePath;
	std::string workingDirectory;
	std::vector<std::string> extraArguments;
	std::string modelFlag = "--model";
	std::string imageFlag = "--image";
	std::string outputFlag = "--output";
	std::string pointXFlag = "--point-x";
	std::string pointYFlag = "--point-y";
	std::string pointLabelFlag = "--point-label";

	bool isConfigured() const {
		return !executablePath.empty();
	}
};

struct ofxGgmlSamImage {
	int width = 0;
	int height = 0;
	int channels = 0;
	std::vector<std::uint8_t> pixels;

	bool isAllocated() const {
		return width > 0 && height > 0 && channels > 0 &&
			pixels.size() == static_cast<std::size_t>(width) *
				static_cast<std::size_t>(height) *
				static_cast<std::size_t>(channels);
	}
};

struct ofxGgmlSamRequest {
	std::string modelPath;
	ofxGgmlSamImage image;
	std::vector<ofxGgmlSamPoint> points;
	ofxGgmlSamExternalAdapterSettings external;
};

struct ofxGgmlSamMask {
	int width = 0;
	int height = 0;
	std::vector<float> values;
	float score = 0.0f;

	bool isAllocated() const {
		return width > 0 && height > 0 && !values.empty();
	}
};

struct ofxGgmlSamResult {
	bool success = false;
	std::string errorMessage;
	std::vector<ofxGgmlSamMask> masks;

	bool isOk() const {
		return success;
	}

	bool isError() const {
		return !success;
	}

	explicit operator bool() const {
		return isOk();
	}
};
