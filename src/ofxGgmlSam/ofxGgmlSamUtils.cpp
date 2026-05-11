#include "ofxGgmlSamUtils.h"

#include <cmath>

namespace {
ofxGgmlSamValidation makeValidationError(const std::string & message) {
	ofxGgmlSamValidation validation;
	validation.success = false;
	validation.errorMessage = message;
	return validation;
}

ofxGgmlSamValidation makeValidationOk() {
	ofxGgmlSamValidation validation;
	validation.success = true;
	return validation;
}
}

float ofxGgmlSamClamp01(float value) {
	if (value < 0.0f) {
		return 0.0f;
	}
	if (value > 1.0f) {
		return 1.0f;
	}
	return value;
}

ofxGgmlSamPoint ofxGgmlSamMakePoint(
	float normalizedX,
	float normalizedY,
	bool positive) {
	ofxGgmlSamPoint point;
	point.x = ofxGgmlSamClamp01(normalizedX);
	point.y = ofxGgmlSamClamp01(normalizedY);
	point.positive = positive;
	return point;
}

ofxGgmlSamPoint ofxGgmlSamMakePointFromPixels(
	float x,
	float y,
	int width,
	int height,
	bool positive) {
	const float normalizedX = width > 1 ? x / static_cast<float>(width - 1) : 0.0f;
	const float normalizedY = height > 1 ? y / static_cast<float>(height - 1) : 0.0f;
	return ofxGgmlSamMakePoint(normalizedX, normalizedY, positive);
}

ofxGgmlSamResult ofxGgmlSamMakeError(const std::string & message) {
	ofxGgmlSamResult result;
	result.success = false;
	result.errorMessage = message;
	return result;
}

ofxGgmlSamValidation ofxGgmlSamValidateImage(
	const ofxGgmlSamImage & image) {
	if (image.width <= 0 || image.height <= 0) {
		return makeValidationError("SAM image width and height must be positive.");
	}
	if (image.channels <= 0) {
		return makeValidationError("SAM image channel count must be positive.");
	}
	const auto expectedSize =
		static_cast<std::size_t>(image.width) *
		static_cast<std::size_t>(image.height) *
		static_cast<std::size_t>(image.channels);
	if (image.pixels.size() != expectedSize) {
		return makeValidationError("SAM image pixel data does not match width, height, and channels.");
	}
	return makeValidationOk();
}

ofxGgmlSamValidation ofxGgmlSamValidateRequest(
	const ofxGgmlSamRequest & request) {
	const auto imageValidation = ofxGgmlSamValidateImage(request.image);
	if (!imageValidation) {
		return imageValidation;
	}
	if (request.points.empty()) {
		return makeValidationError("SAM request needs at least one point prompt.");
	}
	for (const auto & point : request.points) {
		if (!std::isfinite(point.x) || !std::isfinite(point.y)) {
			return makeValidationError("SAM point coordinates must be finite.");
		}
		if (point.x < 0.0f || point.x > 1.0f ||
			point.y < 0.0f || point.y > 1.0f) {
			return makeValidationError("SAM point coordinates must be normalized to [0, 1].");
		}
	}
	return makeValidationOk();
}
