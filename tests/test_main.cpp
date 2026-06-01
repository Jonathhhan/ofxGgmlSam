#include "ofxGgmlSam.h"

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
	OFXGGMLSAM_EXPECT(OFXGGML_SAM_VERSION_MAJOR == 1);
	OFXGGMLSAM_EXPECT(OFXGGML_SAM_VERSION_MINOR == 0);
	OFXGGMLSAM_EXPECT(OFXGGML_SAM_VERSION_PATCH == 1);
	OFXGGMLSAM_EXPECT(std::string(OFXGGML_SAM_VERSION_STRING) == "1.0.1");
	OFXGGMLSAM_EXPECT(std::string(ofxGgmlSamGetVersionString()) == "1.0.1");
	OFXGGMLSAM_EXPECT(OFXGGML_HAS_SAMCPP == 0 || OFXGGML_HAS_SAMCPP == 1);
	OFXGGMLSAM_EXPECT(OFXGGML_HAS_SAM3 == 0 || OFXGGML_HAS_SAM3 == 1);

	ofxGgmlSamImage image;
	OFXGGMLSAM_EXPECT(!image.isAllocated());
	image.width = 2;
	image.height = 2;
	image.channels = 3;
	image.pixels.assign(1, 255);
	OFXGGMLSAM_EXPECT(!image.isAllocated());
	image.pixels.assign(12, 255);
	OFXGGMLSAM_EXPECT(image.isAllocated());
	OFXGGMLSAM_EXPECT(ofxGgmlSamValidateImage(image).isOk());

	const auto clampedPoint = ofxGgmlSamMakePoint(2.0f, -1.0f, false);
	OFXGGMLSAM_EXPECT(clampedPoint.x == 1.0f);
	OFXGGMLSAM_EXPECT(clampedPoint.y == 0.0f);
	OFXGGMLSAM_EXPECT(!clampedPoint.positive);

	const auto pixelPoint = ofxGgmlSamMakePointFromPixels(1.0f, 1.0f, 3, 3);
	OFXGGMLSAM_EXPECT(pixelPoint.x == 0.5f);
	OFXGGMLSAM_EXPECT(pixelPoint.y == 0.5f);

	const auto clampedBox = ofxGgmlSamMakeBox(0.9f, -1.0f, 0.1f, 2.0f, false);
	OFXGGMLSAM_EXPECT(clampedBox.x0 == 0.1f);
	OFXGGMLSAM_EXPECT(clampedBox.y0 == 0.0f);
	OFXGGMLSAM_EXPECT(clampedBox.x1 == 0.9f);
	OFXGGMLSAM_EXPECT(clampedBox.y1 == 1.0f);
	OFXGGMLSAM_EXPECT(!clampedBox.positive);

	const auto pixelBox = ofxGgmlSamMakeBoxFromPixels(1.0f, 1.0f, 3.0f, 3.0f, 5, 5);
	OFXGGMLSAM_EXPECT(pixelBox.x0 == 0.25f);
	OFXGGMLSAM_EXPECT(pixelBox.y0 == 0.25f);
	OFXGGMLSAM_EXPECT(pixelBox.x1 == 0.75f);
	OFXGGMLSAM_EXPECT(pixelBox.y1 == 0.75f);

	ofxGgmlSamInference inference;
	OFXGGMLSAM_EXPECT(!inference.isConfigured());
	OFXGGMLSAM_EXPECT(inference.getBackendName() == "SamBridge");

	ofxGgmlSamRequest request;
	request.image = image;
	request.points.push_back(ofxGgmlSamMakePoint(0.5f, 0.5f, true));
	OFXGGMLSAM_EXPECT(ofxGgmlSamValidateRequest(request).isOk());

	const auto missing = inference.segment(request);
	OFXGGMLSAM_EXPECT(missing.isError());
	OFXGGMLSAM_EXPECT(!missing.errorMessage.empty());

	ofxGgmlSamExternalBackend externalBackend;
	OFXGGMLSAM_EXPECT(externalBackend.getBackendName() == "external-sam");
	OFXGGMLSAM_EXPECT(!externalBackend.isConfigured());
	const auto missingExternalConfig = externalBackend.segment(request);
	OFXGGMLSAM_EXPECT(missingExternalConfig.isError());
	OFXGGMLSAM_EXPECT(missingExternalConfig.errorMessage.find("not configured") != std::string::npos);

	ofxGgmlSamExternalAdapterSettings externalSettings;
	externalSettings.executablePath = "missing-local-sam-adapter.exe";
	externalBackend.setSettings(externalSettings);
	OFXGGMLSAM_EXPECT(externalBackend.isConfigured());
	OFXGGMLSAM_EXPECT(externalBackend.getSettings().executablePath == externalSettings.executablePath);
	const auto missingExternalExecutable = externalBackend.segment(request);
	OFXGGMLSAM_EXPECT(missingExternalExecutable.isError());
	OFXGGMLSAM_EXPECT(missingExternalExecutable.errorMessage.find("executable was not found") != std::string::npos);

	auto externalRequest = request;
	externalRequest.external.executablePath = "missing-request-sam-adapter.exe";
	const auto requestExternalExecutable = ofxGgmlSamExternalBackend().segment(externalRequest);
	OFXGGMLSAM_EXPECT(requestExternalExecutable.isError());
	OFXGGMLSAM_EXPECT(requestExternalExecutable.errorMessage.find("executable was not found") != std::string::npos);

	int callCount = 0;
	auto backend = ofxGgmlSamInference::createBridgeBackend(
		[&callCount](const ofxGgmlSamRequest & request) {
			++callCount;
			ofxGgmlSamResult result;
			result.success =
				request.image.isAllocated() &&
				(!request.points.empty() || !request.boxes.empty());
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
	OFXGGMLSAM_EXPECT(result.backendName == "FakeSam");
	OFXGGMLSAM_EXPECT(result.masks.size() == 1);
	OFXGGMLSAM_EXPECT(result.masks.front().isAllocated());
	OFXGGMLSAM_EXPECT(callCount == 1);

	const auto pointResult = inference.segmentPoint(image, { 0.25f, 0.75f, true });
	OFXGGMLSAM_EXPECT(pointResult.isOk());
	OFXGGMLSAM_EXPECT(callCount == 2);

	const auto boxResult = inference.segmentBox(
		image,
		ofxGgmlSamMakeBox(0.25f, 0.25f, 0.75f, 0.75f, true));
	OFXGGMLSAM_EXPECT(boxResult.isOk());
	OFXGGMLSAM_EXPECT(callCount == 3);

	auto secondRequest = request;
	secondRequest.imagePath = "second-image.ppm";
	secondRequest.points.front() = ofxGgmlSamMakePoint(0.25f, 0.25f, true);
	const auto batchResults = inference.segmentBatch({ request, secondRequest });
	OFXGGMLSAM_EXPECT(batchResults.size() == 2);
	OFXGGMLSAM_EXPECT(batchResults[0].isOk());
	OFXGGMLSAM_EXPECT(batchResults[1].isOk());
	OFXGGMLSAM_EXPECT(batchResults[0].backendName == "FakeSam");
	OFXGGMLSAM_EXPECT(batchResults[1].backendName == "FakeSam");
	OFXGGMLSAM_EXPECT(batchResults[1].imagePath == "second-image.ppm");
	OFXGGMLSAM_EXPECT(callCount == 5);

	ofxGgmlSamRequest invalidBatchRequest;
	invalidBatchRequest.image = image;
	const auto mixedBatchResults = inference.segmentBatch({ request, invalidBatchRequest });
	OFXGGMLSAM_EXPECT(mixedBatchResults.size() == 2);
	OFXGGMLSAM_EXPECT(mixedBatchResults[0].isOk());
	OFXGGMLSAM_EXPECT(mixedBatchResults[1].isError());
	OFXGGMLSAM_EXPECT(callCount == 6);

	inference.setBackend(nullptr);
	OFXGGMLSAM_EXPECT(!inference.isConfigured());
	OFXGGMLSAM_EXPECT(inference.segment(request).isError());

	ofxGgmlSamCppAdapters::attachBackend(
		inference,
		"missing-ofxGgmlSam-test-sam-model.bin");
	const auto missingSamCpp = inference.segment(request);
	OFXGGMLSAM_EXPECT(missingSamCpp.isError());
	OFXGGMLSAM_EXPECT(missingSamCpp.backendName == "sam.cpp");
	OFXGGMLSAM_EXPECT(!missingSamCpp.errorMessage.empty());

	ofxGgmlSam3Adapters::attachBackend(
		inference,
		"missing-ofxGgmlSam-test-sam3-model.gguf");
	const auto missingSam3 = inference.segment(request);
	OFXGGMLSAM_EXPECT(missingSam3.isError());
	OFXGGMLSAM_EXPECT(missingSam3.backendName == "sam3.cpp");
	OFXGGMLSAM_EXPECT(!missingSam3.errorMessage.empty());

	ofxGgmlSamRequest invalidRequest;
	invalidRequest.image = image;
	OFXGGMLSAM_EXPECT(ofxGgmlSamValidateRequest(invalidRequest).isError());
	OFXGGMLSAM_EXPECT(inference.segment(invalidRequest).isError());

	ofxGgmlSamRequest invalidBoxRequest;
	invalidBoxRequest.image = image;
	invalidBoxRequest.boxes.push_back({ 0.75f, 0.75f, 0.25f, 0.25f, true });
	OFXGGMLSAM_EXPECT(ofxGgmlSamValidateRequest(invalidBoxRequest).isError());

	ofxGgmlSamRequest refinementRequest = request;
	refinementRequest.refinementMask.width = image.width;
	refinementRequest.refinementMask.height = image.height;
	refinementRequest.refinementMask.values.assign(
		static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height),
		0.0f);
	OFXGGMLSAM_EXPECT(refinementRequest.refinementMask.isAllocated());
	OFXGGMLSAM_EXPECT(ofxGgmlSamValidateRequest(refinementRequest).isOk());
	refinementRequest.refinementMask.values.pop_back();
	OFXGGMLSAM_EXPECT(!refinementRequest.refinementMask.isAllocated());
	OFXGGMLSAM_EXPECT(ofxGgmlSamValidateRequest(refinementRequest).isError());

	return EXIT_SUCCESS;
}
