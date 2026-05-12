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
	return EXIT_SUCCESS;
}
