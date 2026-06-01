#include "ofxGgmlSam/ofxGgmlSamExternalBackend.h"
#include "ofxGgmlSam/ofxGgmlSamUtils.h"

#include <cstdlib>
#include <iostream>
#include <string>

int main(int argc, char ** argv) {
	if (argc != 2) {
		std::cerr << "usage: ofxGgmlSam_external_adapter_contract <mock-adapter-exe>\n";
		return EXIT_FAILURE;
	}

	ofxGgmlSamImage image;
	image.width = 16;
	image.height = 16;
	image.channels = 3;
	image.pixels.assign(
		static_cast<std::size_t>(image.width) *
			static_cast<std::size_t>(image.height) *
			static_cast<std::size_t>(image.channels),
		128);

	ofxGgmlSamRequest request;
	request.image = image;
	request.points.push_back(ofxGgmlSamMakePoint(0.5f, 0.5f, true));
	request.points.push_back(ofxGgmlSamMakePoint(0.0f, 0.0f, false));
	request.external.executablePath = argv[1];

	ofxGgmlSamExternalBackend backend;
	const auto result = backend.segment(request);
	if (!result) {
		std::cerr << "external adapter contract failed: " << result.errorMessage << "\n";
		return EXIT_FAILURE;
	}
	if (result.masks.size() != 1 ||
		result.masks.front().width != image.width ||
		result.masks.front().height != image.height ||
		!result.masks.front().isAllocated()) {
		std::cerr << "external adapter returned an invalid mask\n";
		return EXIT_FAILURE;
	}
	const auto center =
		static_cast<std::size_t>(image.height / 2) *
		static_cast<std::size_t>(image.width) +
		static_cast<std::size_t>(image.width / 2);
	if (result.masks.front().values[center] <= 0.5f) {
		std::cerr << "external adapter mask did not include the prompted center point\n";
		return EXIT_FAILURE;
	}
	if (result.masks.front().values.front() >= 0.5f) {
		std::cerr << "external adapter mask did not apply the negative corner point\n";
		return EXIT_FAILURE;
	}

	ofxGgmlSamRequest boxRequest;
	boxRequest.image = image;
	boxRequest.boxes.push_back(ofxGgmlSamMakeBox(0.25f, 0.25f, 0.75f, 0.75f, true));
	boxRequest.external.executablePath = argv[1];

	const auto boxResult = backend.segment(boxRequest);
	if (!boxResult) {
		std::cerr << "external adapter box contract failed: " << boxResult.errorMessage << "\n";
		return EXIT_FAILURE;
	}
	if (boxResult.masks.size() != 1 ||
		boxResult.masks.front().width != image.width ||
		boxResult.masks.front().height != image.height ||
		!boxResult.masks.front().isAllocated()) {
		std::cerr << "external adapter returned an invalid box mask\n";
		return EXIT_FAILURE;
	}
	if (boxResult.masks.front().values[center] <= 0.5f) {
		std::cerr << "external adapter box mask did not include the box center\n";
		return EXIT_FAILURE;
	}
	if (boxResult.masks.front().values.front() >= 0.5f) {
		std::cerr << "external adapter box mask leaked into the image corner\n";
		return EXIT_FAILURE;
	}

	ofxGgmlSamRequest refinementRequest;
	refinementRequest.image = image;
	refinementRequest.points.push_back(ofxGgmlSamMakePoint(0.5f, 0.5f, true));
	refinementRequest.refinementMask.width = image.width;
	refinementRequest.refinementMask.height = image.height;
	refinementRequest.refinementMask.values.assign(
		static_cast<std::size_t>(image.width) *
			static_cast<std::size_t>(image.height),
		0.0f);
	const auto topRight =
		static_cast<std::size_t>(image.width - 1);
	refinementRequest.refinementMask.values[topRight] = 1.0f;
	refinementRequest.external.executablePath = argv[1];

	const auto refinementResult = backend.segment(refinementRequest);
	if (!refinementResult) {
		std::cerr << "external adapter refinement contract failed: " << refinementResult.errorMessage << "\n";
		return EXIT_FAILURE;
	}
	if (refinementResult.masks.size() != 1 ||
		refinementResult.masks.front().values[topRight] <= 0.5f) {
		std::cerr << "external adapter did not pass the refinement mask to the runner\n";
		return EXIT_FAILURE;
	}
	return EXIT_SUCCESS;
}
