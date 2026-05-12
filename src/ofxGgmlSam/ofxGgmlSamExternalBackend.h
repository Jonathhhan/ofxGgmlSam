#pragma once

#include "ofxGgmlSamInference.h"

class ofxGgmlSamExternalBackend : public ofxGgmlSamBackend {
public:
	explicit ofxGgmlSamExternalBackend(
		ofxGgmlSamExternalAdapterSettings settings = {});

	void setSettings(const ofxGgmlSamExternalAdapterSettings & settings);
	ofxGgmlSamExternalAdapterSettings getSettings() const;

	bool isConfigured() const override;
	std::string getBackendName() const override;
	ofxGgmlSamResult segment(const ofxGgmlSamRequest & request) const override;

private:
	ofxGgmlSamExternalAdapterSettings settings;
};
