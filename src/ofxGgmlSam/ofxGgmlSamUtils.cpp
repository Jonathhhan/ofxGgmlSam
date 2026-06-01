#include "ofxGgmlSamUtils.h"

#include <algorithm>
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

ofxGgmlSamBox ofxGgmlSamMakeBox(
	float normalizedX0,
	float normalizedY0,
	float normalizedX1,
	float normalizedY1,
	bool positive) {
	const auto clampedX0 = ofxGgmlSamClamp01(normalizedX0);
	const auto clampedY0 = ofxGgmlSamClamp01(normalizedY0);
	const auto clampedX1 = ofxGgmlSamClamp01(normalizedX1);
	const auto clampedY1 = ofxGgmlSamClamp01(normalizedY1);
	ofxGgmlSamBox box;
	box.x0 = std::min(clampedX0, clampedX1);
	box.y0 = std::min(clampedY0, clampedY1);
	box.x1 = std::max(clampedX0, clampedX1);
	box.y1 = std::max(clampedY0, clampedY1);
	box.positive = positive;
	return box;
}

ofxGgmlSamBox ofxGgmlSamMakeBoxFromPixels(
	float x0,
	float y0,
	float x1,
	float y1,
	int width,
	int height,
	bool positive) {
	const float denominatorX = width > 1 ? static_cast<float>(width - 1) : 1.0f;
	const float denominatorY = height > 1 ? static_cast<float>(height - 1) : 1.0f;
	return ofxGgmlSamMakeBox(
		x0 / denominatorX,
		y0 / denominatorY,
		x1 / denominatorX,
		y1 / denominatorY,
		positive);
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
	if (request.points.empty() && request.boxes.empty()) {
		return makeValidationError("SAM request needs at least one point or box prompt.");
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
	for (const auto & box : request.boxes) {
		if (!std::isfinite(box.x0) || !std::isfinite(box.y0) ||
			!std::isfinite(box.x1) || !std::isfinite(box.y1)) {
			return makeValidationError("SAM box coordinates must be finite.");
		}
		if (box.x0 < 0.0f || box.x0 > 1.0f ||
			box.y0 < 0.0f || box.y0 > 1.0f ||
			box.x1 < 0.0f || box.x1 > 1.0f ||
			box.y1 < 0.0f || box.y1 > 1.0f) {
			return makeValidationError("SAM box coordinates must be normalized to [0, 1].");
		}
		if (box.x0 >= box.x1 || box.y0 >= box.y1) {
			return makeValidationError("SAM box coordinates must describe a positive-area rectangle.");
		}
	}
	if (!request.refinementMask.values.empty()) {
		if (!request.refinementMask.isAllocated()) {
			return makeValidationError("SAM refinement mask dimensions must match its value count.");
		}
		if (request.refinementMask.width != request.image.width ||
			request.refinementMask.height != request.image.height) {
			return makeValidationError("SAM refinement mask dimensions must match the request image.");
		}
		for (const auto value : request.refinementMask.values) {
			if (!std::isfinite(value)) {
				return makeValidationError("SAM refinement mask values must be finite.");
			}
		}
	}
	return makeValidationOk();
}
