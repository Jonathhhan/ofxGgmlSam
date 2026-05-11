#pragma once

#include "ofMain.h"
#include "ofxGgmlSam.h"

class ofApp : public ofBaseApp {
public:
	void setup() override;
	void draw() override;

private:
	ofxGgmlSamRequest request;
	ofxGgmlSamInference inference;
	ofxGgmlSamResult lastResult;
};
