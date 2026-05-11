#include "ofxGgmlSam/ofxGgmlSamInference.h"

#include <cstdlib>
#include <iostream>
#include <string>

#define OFXGGMLSAM_EXPECT(condition) \
	do { \
		if (!(condition)) { \
			std::cerr << "Expectation failed: " #condition << std::endl; \
			return EXIT_FAILURE; \
		} \
	} while (false)

int main() {
	ofxGgmlSamImage image;
	OFXGGMLSAM_EXPECT(!image.isAllocated());
	image.width = 2;
	image.height = 2;
	image.channels = 3;
	image.pixels.assign(12, 255);
	OFXGGMLSAM_EXPECT(image.isAllocated());

	ofxGgmlSamInference inference;
	OFXGGMLSAM_EXPECT(!inference.isConfigured());
	OFXGGMLSAM_EXPECT(inference.getBackendName() == "SamBridge");

	ofxGgmlSamRequest request;
	request.image = image;
	request.points.push_back({ 0.5f, 0.5f, true });

	const auto missing = inference.segment(request);
	OFXGGMLSAM_EXPECT(missing.isError());
	OFXGGMLSAM_EXPECT(!missing.errorMessage.empty());

	int callCount = 0;
	auto backend = ofxGgmlSamInference::createBridgeBackend(
		[&callCount](const ofxGgmlSamRequest & request) {
			++callCount;
			ofxGgmlSamResult result;
			result.success = request.image.isAllocated() && !request.points.empty();
			ofxGgmlSamMask mask;
			mask.width = 1;
			mask.height = 1;
			mask.values.push_back(1.0f);
			mask.score = 0.75f;
			result.masks.push_back(mask);
			return result;
		},
		"FakeSam");

	inference.setBackend(backend);
	OFXGGMLSAM_EXPECT(inference.isConfigured());
	OFXGGMLSAM_EXPECT(inference.getBackendName() == "FakeSam");

	const auto result = inference.segment(request);
	OFXGGMLSAM_EXPECT(result);
	OFXGGMLSAM_EXPECT(result.isOk());
	OFXGGMLSAM_EXPECT(result.masks.size() == 1);
	OFXGGMLSAM_EXPECT(result.masks.front().isAllocated());
	OFXGGMLSAM_EXPECT(callCount == 1);

	const auto pointResult = inference.segmentPoint(image, { 0.25f, 0.75f, true });
	OFXGGMLSAM_EXPECT(pointResult.isOk());
	OFXGGMLSAM_EXPECT(callCount == 2);

	inference.setBackend(nullptr);
	OFXGGMLSAM_EXPECT(!inference.isConfigured());
	OFXGGMLSAM_EXPECT(inference.segment(request).isError());

	return EXIT_SUCCESS;
}
