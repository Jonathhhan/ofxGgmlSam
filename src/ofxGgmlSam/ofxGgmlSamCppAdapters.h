#pragma once

#include "ofxGgmlSamInference.h"

#include <algorithm>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>

#if defined(OFXGGML_ENABLE_SAMCPP_ADAPTER) && defined(__has_include)
#if __has_include("sam.h")
#define OFXGGML_HAS_SAMCPP 1
#include "sam.h"
#else
#define OFXGGML_HAS_SAMCPP 0
#endif
#else
#define OFXGGML_HAS_SAMCPP 0
#endif

namespace ofxGgmlSamCppAdapters {

struct RuntimeOptions {
	int threads = -1;
	int seed = -1;
	int maskOnValue = 255;
	int maskOffValue = 0;
};

inline int resolveThreadCount(const RuntimeOptions & options) {
	if (options.threads > 0) {
		return options.threads;
	}
	const unsigned int detected = std::thread::hardware_concurrency();
	return detected > 0 ? static_cast<int>(detected) : 4;
}

inline int resolveThreadCount(
	const ofxGgmlSamRequest & request,
	const RuntimeOptions & options) {
	if (request.threads > 0) {
		return request.threads;
	}
	return resolveThreadCount(options);
}

#if OFXGGML_HAS_SAMCPP

using ModelHandle = std::shared_ptr<sam_state>;

inline ModelHandle manageModelHandle(ModelHandle model) {
	if (!model) {
		return {};
	}
	return ModelHandle(
		model.get(),
		[model = std::move(model)](sam_state * state) mutable {
			if (state) {
				sam_deinit(*state);
			}
			model.reset();
		});
}

inline ModelHandle loadModel(
	const std::string & modelPath,
	const RuntimeOptions & options = {},
	std::string * error = nullptr) {
	if (modelPath.empty()) {
		if (error) {
			*error = "sam.cpp model path is empty";
		}
		return {};
	}

	sam_params params;
	params.model = modelPath;
	params.n_threads = resolveThreadCount(options);
	params.seed = options.seed;
	auto model = sam_load_model(params);
	if (!model) {
		if (error) {
			*error = "failed to load sam.cpp model: " + modelPath;
		}
		return {};
	}
	return manageModelHandle(std::move(model));
}

inline bool fillSamImage(
	const ofxGgmlSamRequest & request,
	sam_image_u8 & image,
	std::string * error = nullptr) {
	if (!request.image.isAllocated()) {
		if (error) {
			*error = "sam.cpp adapter requires an allocated image";
		}
		return false;
	}
	image.nx = request.image.width;
	image.ny = request.image.height;
	image.data.clear();
	image.data.reserve(
		static_cast<size_t>(request.image.width) *
		static_cast<size_t>(request.image.height) *
		3u);
	for (int y = 0; y < request.image.height; ++y) {
		for (int x = 0; x < request.image.width; ++x) {
			const auto base =
				(static_cast<size_t>(y) * static_cast<size_t>(request.image.width) +
					static_cast<size_t>(x)) *
				static_cast<size_t>(request.image.channels);
			const auto r = request.image.pixels[base];
			const auto g = request.image.channels > 1 ? request.image.pixels[base + 1] : r;
			const auto b = request.image.channels > 2 ? request.image.pixels[base + 2] : r;
			image.data.push_back(r);
			image.data.push_back(g);
			image.data.push_back(b);
		}
	}
	return true;
}

inline ofxGgmlSamResult segmentWithModel(
	const ModelHandle & model,
	const ofxGgmlSamRequest & request,
	const RuntimeOptions & options = {},
	const std::string & modelPath = {}) {
	ofxGgmlSamResult result;
	result.backendName = "sam.cpp";
	result.imagePath = request.imagePath;
	if (!model) {
		result.errorMessage = "sam.cpp model is not loaded";
		return result;
	}
	if (request.refinementMask.isAllocated()) {
		result.errorMessage =
			"sam.cpp adapter mask refinement is not wired yet; use the external adapter for refinement masks";
		return result;
	}
	if (!request.boxes.empty()) {
		result.errorMessage =
			"sam.cpp adapter box prompts are not wired yet; use the external adapter for box prompts";
		return result;
	}
	if (request.points.empty()) {
		result.errorMessage = "sam.cpp adapter requires at least one point prompt";
		return result;
	}
	if (!request.points.front().positive) {
		result.errorMessage =
			"sam.cpp adapter currently supports positive point prompts only";
		return result;
	}

	sam_image_u8 image;
	if (!fillSamImage(request, image, &result.errorMessage)) {
		return result;
	}

	const auto started = std::chrono::steady_clock::now();
	const int threads = resolveThreadCount(request, options);
	if (!sam_compute_embd_img(image, threads, *model)) {
		result.errorMessage = "sam.cpp failed to compute image embeddings";
		return result;
	}

	const auto & point = request.points.front();
	const auto masks = sam_compute_masks(
		image,
		threads,
		{ point.x, point.y },
		*model,
		options.maskOnValue,
		options.maskOffValue);
	if (masks.empty()) {
		result.errorMessage = "sam.cpp did not produce any masks";
		return result;
	}

	const size_t maskCount = request.returnMultipleMasks ? masks.size() : 1u;
	for (size_t i = 0; i < maskCount; ++i) {
		ofxGgmlSamMask mask;
		mask.width = masks[i].nx;
		mask.height = masks[i].ny;
		mask.values.reserve(masks[i].data.size());
		const float denominator = options.maskOnValue > 0
			? static_cast<float>(options.maskOnValue)
			: 255.0f;
		for (const auto value : masks[i].data) {
			mask.values.push_back(
				std::clamp(static_cast<float>(value) / denominator, 0.0f, 1.0f));
		}
		mask.score = 1.0f;
		result.masks.push_back(std::move(mask));
	}

	result.success = true;
	result.elapsedMs = std::chrono::duration<float, std::milli>(
		std::chrono::steady_clock::now() - started).count();
	result.metadata.push_back({ "backend", "sam.cpp" });
	result.metadata.push_back({ "threads", std::to_string(threads) });
	if (!modelPath.empty()) {
		result.metadata.push_back({ "modelPath", modelPath });
	}
	return result;
}

inline std::shared_ptr<ofxGgmlSamBackend> createBackend(
	ModelHandle model,
	const RuntimeOptions & options = {},
	const std::string & modelPath = {},
	const std::string & displayName = "sam.cpp") {
	auto mutex = std::make_shared<std::mutex>();
	return ofxGgmlSamInference::createBridgeBackend(
		[model, options, modelPath, mutex](const ofxGgmlSamRequest & request) {
			std::lock_guard<std::mutex> lock(*mutex);
			return segmentWithModel(model, request, options, modelPath);
		},
		displayName);
}

inline std::shared_ptr<ofxGgmlSamBackend> createBackend(
	const std::string & modelPath,
	const RuntimeOptions & options = {},
	const std::string & displayName = "sam.cpp") {
	std::string error;
	const auto model = loadModel(modelPath, options, &error);
	if (!model) {
		return ofxGgmlSamInference::createBridgeBackend(
			[error, modelPath](const ofxGgmlSamRequest & request) {
				ofxGgmlSamResult result;
				result.backendName = "sam.cpp";
				result.imagePath = request.imagePath;
				result.errorMessage = error.empty()
					? "failed to load sam.cpp model: " + modelPath
					: error;
				return result;
			},
			displayName);
	}
	return createBackend(model, options, modelPath, displayName);
}

inline void attachBackend(
	ofxGgmlSamInference & inference,
	ModelHandle model,
	const RuntimeOptions & options = {},
	const std::string & modelPath = {},
	const std::string & displayName = "sam.cpp") {
	inference.setBackend(createBackend(model, options, modelPath, displayName));
}

inline void attachBackend(
	ofxGgmlSamInference & inference,
	const std::string & modelPath,
	const RuntimeOptions & options = {},
	const std::string & displayName = "sam.cpp") {
	inference.setBackend(createBackend(modelPath, options, displayName));
}

#else

inline std::shared_ptr<ofxGgmlSamBackend> createBackend(
	const std::string & modelPath,
	const RuntimeOptions & = {},
	const std::string & displayName = "sam.cpp") {
	return ofxGgmlSamInference::createBridgeBackend(
		[modelPath](const ofxGgmlSamRequest & request) {
			ofxGgmlSamResult result;
			result.backendName = "sam.cpp";
			result.imagePath = request.imagePath;
			result.errorMessage =
				"sam.cpp adapter is disabled. Define OFXGGML_ENABLE_SAMCPP_ADAPTER, "
				"add sam.cpp headers, link a compatible sam.cpp runtime, and use a .bin SAM model "
				"before using model: " +
				modelPath;
			return result;
		},
		displayName);
}

inline void attachBackend(
	ofxGgmlSamInference & inference,
	const std::string & modelPath,
	const RuntimeOptions & options = {},
	const std::string & displayName = "sam.cpp") {
	inference.setBackend(createBackend(modelPath, options, displayName));
}

#endif

} // namespace ofxGgmlSamCppAdapters
