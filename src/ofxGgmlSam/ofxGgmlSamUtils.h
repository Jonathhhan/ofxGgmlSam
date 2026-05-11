#pragma once

#include "ofxGgmlSamTypes.h"

#include <string>

struct ofxGgmlSamValidation {
	bool success = false;
	std::string errorMessage;

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

float ofxGgmlSamClamp01(float value);

ofxGgmlSamPoint ofxGgmlSamMakePoint(
	float normalizedX,
	float normalizedY,
	bool positive = true);

ofxGgmlSamPoint ofxGgmlSamMakePointFromPixels(
	float x,
	float y,
	int width,
	int height,
	bool positive = true);

ofxGgmlSamResult ofxGgmlSamMakeError(const std::string & message);

ofxGgmlSamValidation ofxGgmlSamValidateImage(
	const ofxGgmlSamImage & image);

ofxGgmlSamValidation ofxGgmlSamValidateRequest(
	const ofxGgmlSamRequest & request);
