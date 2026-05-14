#include "ofApp.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>

namespace {
	constexpr const char * LogModule = "ofxGgmlSamPointExample";

	std::string getEnvString(const std::string & name) {
		const auto value = std::getenv(name.c_str());
		return value ? std::string(value) : "";
	}

	void copyToBuffer(const std::string & text, char * buffer, std::size_t size) {
		if (size == 0) {
			return;
		}
		std::snprintf(buffer, size, "%s", text.c_str());
	}
}

void ofApp::setup() {
	ofSetWindowTitle("ofxGgmlSam point example");
	gui.setup();

	executablePath = getEnvString("OFXGGML_SAM_EXECUTABLE");
	modelPath = getEnvString("OFXGGML_SAM_MODEL");
	imagePath = getEnvString("OFXGGML_SAM_IMAGE");

	request.points.push_back(ofxGgmlSamMakePoint(0.5f, 0.5f, true));
	inference.setBackend(std::make_shared<ofxGgmlSamExternalBackend>());
	loadImage();
}

void ofApp::draw() {
	ofBackground(18);
	const auto imageRect = getImageRect();

	if (imageLoaded) {
		ofSetColor(255);
		image.draw(imageRect);
		if (maskTexture.isAllocated()) {
			ofSetColor(0, 190, 255, 105);
			maskTexture.draw(imageRect);
		}
		ofSetColor(request.points.front().positive ? ofColor::limeGreen : ofColor::red);
		ofDrawCircle(
			imageRect.x + request.points.front().x * imageRect.width,
			imageRect.y + request.points.front().y * imageRect.height,
			6.0f);
	} else {
		ofSetColor(80);
		ofDrawRectangle(imageRect);
		ofSetColor(230);
		ofDrawBitmapString("Set OFXGGML_SAM_IMAGE or enter an image path.", imageRect.x + 16, imageRect.y + 28);
	}

	gui.begin();
	ImGui::SetNextWindowSize(ImVec2(480, 330), ImGuiCond_FirstUseEver);
	ImGui::Begin("ofxGgmlSam Point Example");

	static char executableBuffer[1024];
	static char modelBuffer[1024];
	static char imageBuffer[1024];
	static bool buffersInitialized = false;
	if (!buffersInitialized) {
		copyToBuffer(executablePath, executableBuffer, sizeof(executableBuffer));
		copyToBuffer(modelPath, modelBuffer, sizeof(modelBuffer));
		copyToBuffer(imagePath, imageBuffer, sizeof(imageBuffer));
		buffersInitialized = true;
	}

	if (ImGui::InputText("Executable", executableBuffer, sizeof(executableBuffer))) {
		executablePath = executableBuffer;
	}
	if (ImGui::InputText("Model", modelBuffer, sizeof(modelBuffer))) {
		modelPath = modelBuffer;
	}
	if (ImGui::InputText("Image", imageBuffer, sizeof(imageBuffer))) {
		imagePath = imageBuffer;
	}
	if (ImGui::Button("Load Image")) {
		loadImage();
	}
	ImGui::SameLine();
	if (ImGui::Button("Run")) {
		runSegmentation();
	}
	ImGui::SameLine();
	ImGui::Checkbox("Auto", &autoRun);

	auto & point = request.points.front();
	bool pointChanged = false;
	pointChanged |= ImGui::SliderFloat("Point X", &point.x, 0.0f, 1.0f);
	pointChanged |= ImGui::SliderFloat("Point Y", &point.y, 0.0f, 1.0f);
	pointChanged |= ImGui::Checkbox("Positive", &point.positive);
	if (pointChanged && autoRun) {
		runSegmentation();
	}

	ImGui::Separator();
	ImGui::TextWrapped("Backend: %s", inference.getBackendName().c_str());
	ImGui::TextWrapped("Status: %s", status.c_str());
	if (lastResult) {
		ImGui::Text("Masks: %d", static_cast<int>(lastResult.masks.size()));
		if (!lastResult.masks.empty()) {
			ImGui::Text("Score: %.3f", lastResult.masks.front().score);
		}
	}
	ImGui::End();
	gui.end();
}

void ofApp::mousePressed(int x, int y, int button) {
	if (button != OF_MOUSE_BUTTON_LEFT || request.points.empty() || !imageLoaded) {
		return;
	}
	const auto imageRect = getImageRect();
	if (!imageRect.inside(x, y)) {
		return;
	}
	request.points.front() = ofxGgmlSamMakePoint(
		(static_cast<float>(x) - imageRect.x) / imageRect.width,
		(static_cast<float>(y) - imageRect.y) / imageRect.height,
		true);
	if (autoRun) {
		runSegmentation();
	}
}

void ofApp::loadImage() {
	maskTexture.clear();
	lastResult = {};
	imageLoaded = false;
	if (imagePath.empty()) {
		setStatus("image path is empty", true);
		return;
	}
	if (!image.load(imagePath)) {
		setStatus("could not load image: " + imagePath, true);
		return;
	}
	imageLoaded = true;
	updateRequestImage();
	setStatus("image loaded");
}

void ofApp::runSegmentation() {
	if (!imageLoaded) {
		setStatus("load an image first", true);
		return;
	}
	updateRequestImage();
	request.modelPath = modelPath;
	request.external.executablePath = executablePath;
	lastResult = inference.segment(request);
	if (!lastResult) {
		setStatus(lastResult.errorMessage, true);
		maskTexture.clear();
		return;
	}
	updateMaskTexture();
	setStatus("segmentation complete");
}

void ofApp::updateRequestImage() {
	const auto & pixels = image.getPixels();
	request.image.width = pixels.getWidth();
	request.image.height = pixels.getHeight();
	request.image.channels = pixels.getNumChannels();
	request.image.pixels.assign(pixels.getData(), pixels.getData() + pixels.size());
}

void ofApp::updateMaskTexture() {
	maskTexture.clear();
	if (!lastResult || lastResult.masks.empty() || !lastResult.masks.front().isAllocated()) {
		return;
	}
	const auto & mask = lastResult.masks.front();
	ofPixels pixels;
	pixels.allocate(mask.width, mask.height, OF_PIXELS_RGBA);
	for (int y = 0; y < mask.height; ++y) {
		for (int x = 0; x < mask.width; ++x) {
			const auto value = ofClamp(mask.values[static_cast<std::size_t>(y * mask.width + x)], 0.0f, 1.0f);
			pixels.setColor(x, y, ofColor(0, 190, 255, static_cast<unsigned char>(value * 255.0f)));
		}
	}
	maskTexture.loadData(pixels);
}

void ofApp::setStatus(const std::string & message, bool warning) {
	status = message;
	if (warning) {
		ofLogWarning(LogModule) << message;
	} else {
		ofLogNotice(LogModule) << message;
	}
}

ofRectangle ofApp::getImageRect() const {
	const float margin = 24.0f;
	const float top = 24.0f;
	const float maxWidth = ofGetWidth() - margin * 2.0f;
	const float maxHeight = ofGetHeight() - top - margin;
	if (!imageLoaded || image.getWidth() <= 0 || image.getHeight() <= 0) {
		return { margin, top, maxWidth, maxHeight };
	}
	const float scale = std::min(maxWidth / image.getWidth(), maxHeight / image.getHeight());
	const float width = image.getWidth() * scale;
	const float height = image.getHeight() * scale;
	return { margin, top, width, height };
}
