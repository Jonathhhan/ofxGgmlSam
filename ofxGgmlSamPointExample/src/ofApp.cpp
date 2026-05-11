#include "ofApp.h"

void ofApp::setup() {
	ofSetWindowTitle("ofxGgmlSam point example");
	request.points.push_back({ 0.5f, 0.5f, true });
}

void ofApp::draw() {
	ofBackground(18);
	ofSetColor(240);
	ofDrawBitmapString("ofxGgmlSam point example", 24, 32);
	ofDrawBitmapString("Skeleton only: model/image loading and mask preview come next.", 24, 56);
	ofDrawBitmapString("Default point: " + ofToString(request.points.front().x) + ", " +
		ofToString(request.points.front().y), 24, 80);
}
