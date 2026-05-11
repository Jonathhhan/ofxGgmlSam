#include "ofxGgmlSamInference.h"
#include "ofxGgmlSamUtils.h"

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
	if (segmentFunction) {
		return segmentFunction(request);
	}

	return ofxGgmlSamMakeError(
		"ofxGgmlSam backend is not configured. Install or assign a SAM adapter first.");
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
