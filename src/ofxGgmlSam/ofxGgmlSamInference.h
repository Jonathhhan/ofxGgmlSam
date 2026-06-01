#pragma once

#include "ofxGgmlSamTypes.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

class ofxGgmlSamBackend {
public:
	virtual ~ofxGgmlSamBackend() = default;

	virtual bool isConfigured() const = 0;
	virtual std::string getBackendName() const = 0;
	virtual ofxGgmlSamResult segment(const ofxGgmlSamRequest & request) const = 0;
};

class ofxGgmlSamBridgeBackend : public ofxGgmlSamBackend {
public:
	using SegmentFunction = std::function<ofxGgmlSamResult(
		const ofxGgmlSamRequest &)>;

	explicit ofxGgmlSamBridgeBackend(
		SegmentFunction segmentFunction = {},
		std::string displayName = "SamBridge");

	void setSegmentFunction(SegmentFunction segmentFunction);

	bool isConfigured() const override;
	std::string getBackendName() const override;
	ofxGgmlSamResult segment(const ofxGgmlSamRequest & request) const override;

private:
	SegmentFunction segmentFunction;
	std::string displayName;
};

class ofxGgmlSamInference {
public:
	ofxGgmlSamInference();

	static std::shared_ptr<ofxGgmlSamBackend> createBridgeBackend(
		ofxGgmlSamBridgeBackend::SegmentFunction segmentFunction = {},
		const std::string & displayName = "SamBridge");

	void setBackend(std::shared_ptr<ofxGgmlSamBackend> backend);
	std::shared_ptr<ofxGgmlSamBackend> getBackend() const;

	bool isConfigured() const;
	std::string getBackendName() const;

	ofxGgmlSamResult segment(const ofxGgmlSamRequest & request) const;
	std::vector<ofxGgmlSamResult> segmentBatch(
		const std::vector<ofxGgmlSamRequest> & requests) const;
	ofxGgmlSamResult segmentPoint(
		const ofxGgmlSamImage & image,
		const ofxGgmlSamPoint & point,
		const std::string & modelPath = "") const;
	ofxGgmlSamResult segmentBox(
		const ofxGgmlSamImage & image,
		const ofxGgmlSamBox & box,
		const std::string & modelPath = "") const;

private:
	std::shared_ptr<ofxGgmlSamBackend> backendPtr;
};
