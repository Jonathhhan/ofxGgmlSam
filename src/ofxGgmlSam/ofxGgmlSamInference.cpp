#include "ofxGgmlSamInference.h"
#include "ofxGgmlSamUtils.h"

#include <chrono>
#include <utility>

ofxGgmlSamBridgeBackend::ofxGgmlSamBridgeBackend(
	SegmentFunction segmentFunction,
	std::string displayName)
	: segmentFunction(std::move(segmentFunction))
	, displayName(std::move(displayName)) {
}

void ofxGgmlSamBridgeBackend::setSegmentFunction(
	SegmentFunction segmentFunction) {
	this->segmentFunction = std::move(segmentFunction);
}

bool ofxGgmlSamBridgeBackend::isConfigured() const {
	return static_cast<bool>(segmentFunction);
}

std::string ofxGgmlSamBridgeBackend::getBackendName() const {
	return displayName.empty() ? "SamBridge" : displayName;
}

ofxGgmlSamResult ofxGgmlSamBridgeBackend::segment(
	const ofxGgmlSamRequest & request) const {
	ofxGgmlSamResult result;
	result.backendName = getBackendName();
	result.imagePath = request.imagePath;
	if (segmentFunction) {
		const auto started = std::chrono::steady_clock::now();
		result = segmentFunction(request);
		if (result.backendName.empty()) {
			result.backendName = getBackendName();
		}
		if (result.imagePath.empty()) {
			result.imagePath = request.imagePath;
		}
		if (result.elapsedMs <= 0.0f) {
			result.elapsedMs = std::chrono::duration<float, std::milli>(
				std::chrono::steady_clock::now() - started).count();
		}
		return result;
	}

	result.errorMessage =
		"ofxGgmlSam backend is not configured. Install or assign a SAM adapter first.";
	return result;
}

ofxGgmlSamInference::ofxGgmlSamInference()
	: backendPtr(createBridgeBackend()) {
}

std::shared_ptr<ofxGgmlSamBackend> ofxGgmlSamInference::createBridgeBackend(
	ofxGgmlSamBridgeBackend::SegmentFunction segmentFunction,
	const std::string & displayName) {
	return std::make_shared<ofxGgmlSamBridgeBackend>(
		std::move(segmentFunction),
		displayName);
}

void ofxGgmlSamInference::setBackend(
	std::shared_ptr<ofxGgmlSamBackend> backend) {
	backendPtr = backend ? std::move(backend) : createBridgeBackend();
}

std::shared_ptr<ofxGgmlSamBackend> ofxGgmlSamInference::getBackend() const {
	return backendPtr;
}

bool ofxGgmlSamInference::isConfigured() const {
	return backendPtr && backendPtr->isConfigured();
}

std::string ofxGgmlSamInference::getBackendName() const {
	return backendPtr ? backendPtr->getBackendName() : "SamBridge";
}

ofxGgmlSamResult ofxGgmlSamInference::segment(
	const ofxGgmlSamRequest & request) const {
	const auto validation = ofxGgmlSamValidateRequest(request);
	if (!validation) {
		return ofxGgmlSamMakeError(validation.errorMessage);
	}
	const auto backend = backendPtr ? backendPtr : createBridgeBackend();
	return backend->segment(request);
}

ofxGgmlSamResult ofxGgmlSamInference::segmentPoint(
	const ofxGgmlSamImage & image,
	const ofxGgmlSamPoint & point,
	const std::string & modelPath) const {
	ofxGgmlSamRequest request;
	request.modelPath = modelPath;
	request.image = image;
	request.points.push_back(point);
	return segment(request);
}
