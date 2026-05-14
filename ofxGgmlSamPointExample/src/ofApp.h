#pragma once

#include "ofMain.h"
#include "ofxGgmlSam.h"
#include "ofxImGui.h"

class ofApp : public ofBaseApp {
public:
	void setup() override;
	void draw() override;
	void mousePressed(int x, int y, int button) override;

private:
	void loadImage();
	void runSegmentation();
	void updateRequestImage();
	void updateMaskTexture();
	void setStatus(const std::string & message, bool warning = false);
	ofRectangle getImageRect() const;

	ofxImGui::Gui gui;
	ofxGgmlSamRequest request;
	ofxGgmlSamInference inference;
	ofxGgmlSamResult lastResult;
	ofImage image;
	ofTexture maskTexture;
	std::string executablePath;
	std::string modelPath;
	std::string imagePath;
	std::string status;
	bool imageLoaded = false;
	bool autoRun = false;
};
