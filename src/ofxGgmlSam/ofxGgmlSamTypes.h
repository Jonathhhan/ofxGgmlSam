#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

struct ofxGgmlSamPoint {
	float x = 0.0f;
	float y = 0.0f;
	bool positive = true;
};

struct ofxGgmlSamBox {
	float x0 = 0.0f;
	float y0 = 0.0f;
	float x1 = 1.0f;
	float y1 = 1.0f;
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
	std::string boxX0Flag = "--box-x0";
	std::string boxY0Flag = "--box-y0";
	std::string boxX1Flag = "--box-x1";
	std::string boxY1Flag = "--box-y1";
	std::string boxLabelFlag = "--box-label";
	std::string maskInputFlag = "--mask-input";

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

struct ofxGgmlSamMask {
	int width = 0;
	int height = 0;
	std::vector<float> values;
	float score = 0.0f;

	bool isAllocated() const {
		return width > 0 && height > 0 &&
			values.size() == static_cast<std::size_t>(width) *
				static_cast<std::size_t>(height);
	}
};

struct ofxGgmlSamRequest {
	std::string modelPath;
	std::string imagePath;
	ofxGgmlSamImage image;
	std::vector<ofxGgmlSamPoint> points;
	std::vector<ofxGgmlSamBox> boxes;
	ofxGgmlSamMask refinementMask;
	ofxGgmlSamExternalAdapterSettings external;
	int threads = -1;
	bool returnMultipleMasks = true;
};

struct ofxGgmlSamResult {
	bool success = false;
	float elapsedMs = 0.0f;
	std::string errorMessage;
	std::string backendName;
	std::string imagePath;
	std::vector<ofxGgmlSamMask> masks;
	std::vector<std::pair<std::string, std::string>> metadata;

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
