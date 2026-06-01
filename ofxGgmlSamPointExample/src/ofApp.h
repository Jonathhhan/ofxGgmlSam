#pragma once

#include "ofMain.h"
#include "ofxGgmlSam.h"
#include "ofxImGui.h"

#include <atomic>
#include <cstdint>
#include <exception>

class ofApp : public ofBaseApp {
public:
	void setup() override;
	void update() override;
	void draw() override;
	void exit() override;
	void mousePressed(int x, int y, int button) override;
	void mouseDragged(int x, int y, int button) override;
	void mouseReleased(int x, int y, int button) override;

private:
	struct SegmentationJob {
		ofxGgmlSamRequest request;
		std::string modelPath;
		std::string backendLabel;
		int backendIndex = 0;
		std::uint64_t id = 0;
	};

	struct SegmentationJobResult {
		ofxGgmlSamResult result;
		std::string backendLabel;
		std::uint64_t id = 0;
	};

	class SegmentationWorker : public ofThread {
	public:
		void start();
		void stop();
		bool submit(SegmentationJob job);
		bool tryReceive(SegmentationJobResult & result);
		bool isBusy() const;

	private:
		void threadedFunction() override;
		void configureBackend(const SegmentationJob & job);

		ofThreadChannel<SegmentationJob> jobs;
		ofThreadChannel<SegmentationJobResult> results;
		ofxGgmlSamInference inference;
		std::string cachedModelPath;
		int cachedBackendIndex = -1;
		std::atomic<bool> busy{ false };
	};

	void loadImage();
	bool loadImageFromPath(const std::string & path);
	void loadGeneratedImage();
	std::string findDefaultModelPath() const;
	std::string getBackendLabel() const;
	bool isModelPathCompatibleWithBackend(const std::string & path) const;
	bool ensureModelPath();
	void runSegmentation();
	void ensurePromptDefaults();
	bool isBoxPromptSelected() const;
	ofVec2f getNormalizedImagePoint(int x, int y) const;
	void setBoxFromCorners(const ofVec2f & a, const ofVec2f & b);
	void updateRequestImage();
	void updateMaskTexture();
	void setStatus(const std::string & message, bool warning = false);
	ofRectangle getImageRect() const;

	ofxImGui::Gui gui;
	ofxGgmlSamRequest request;
	SegmentationWorker segmentationWorker;
	ofxGgmlSamResult lastResult;
	ofImage image;
	ofTexture maskTexture;
	std::string modelPath;
	std::string imagePath;
	std::string status;
	int selectedBackendIndex = 0;
	int selectedPromptIndex = 0;
	std::uint64_t nextJobId = 1;
	std::uint64_t latestSubmittedJobId = 0;
	ofVec2f boxDragStart{ 0.25f, 0.25f };
	bool imageLoaded = false;
	bool autoRun = false;
	bool draggingBox = false;
};
