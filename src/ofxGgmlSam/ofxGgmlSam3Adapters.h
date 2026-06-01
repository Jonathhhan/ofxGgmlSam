#pragma once

#include "ofxGgmlSamInference.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>

#if defined(OFXGGML_ENABLE_SAM3_ADAPTER) && defined(__has_include)
#if __has_include("sam3.h")
#define OFXGGML_HAS_SAM3 1
#include "sam3.h"
#else
#define OFXGGML_HAS_SAM3 0
#endif
#else
#define OFXGGML_HAS_SAM3 0
#endif

namespace ofxGgmlSam3Adapters {

struct RuntimeOptions {
	int threads = -1;
	int seed = 42;
	bool useGpu = true;
	int encodeImageSize = 0;
};

inline int resolveThreadCount(const RuntimeOptions & options) {
	if (options.threads > 0) {
		return options.threads;
	}
	const unsigned int detected = std::thread::hardware_concurrency();
	return detected > 0 ? static_cast<int>(detected) : 4;
}

#if OFXGGML_HAS_SAM3

using ModelHandle = std::shared_ptr<sam3_model>;

struct Runtime {
	ModelHandle model;
	sam3_state_ptr state;
	sam3_params params;
	std::string modelPath;
	std::uint64_t cachedImageFingerprint = 0;
	bool hasCachedImage = false;
};

inline sam3_params makeParams(
	const std::string & modelPath,
	const RuntimeOptions & options) {
	sam3_params params;
	params.model_path = modelPath;
	params.n_threads = resolveThreadCount(options);
	params.use_gpu = options.useGpu;
	params.seed = options.seed;
	params.encode_img_size = options.encodeImageSize;
	return params;
}

inline std::shared_ptr<Runtime> loadRuntime(
	const std::string & modelPath,
	const RuntimeOptions & options = {},
	std::string * error = nullptr) {
	if (modelPath.empty()) {
		if (error) {
			*error = "sam3.cpp model path is empty";
		}
		return {};
	}

	auto runtime = std::make_shared<Runtime>();
	runtime->params = makeParams(modelPath, options);
	runtime->modelPath = modelPath;
	runtime->model = sam3_load_model(runtime->params);
	if (!runtime->model) {
		if (error) {
			*error = "failed to load sam3.cpp model: " + modelPath;
		}
		return {};
	}

	runtime->state = sam3_create_state(*runtime->model, runtime->params);
	if (!runtime->state) {
		if (error) {
			*error = "failed to create sam3.cpp inference state: " + modelPath;
		}
		return {};
	}
	return runtime;
}

inline bool fillSam3Image(
	const ofxGgmlSamRequest & request,
	sam3_image & image,
	std::string * error = nullptr) {
	if (!request.image.isAllocated()) {
		if (error) {
			*error = "sam3.cpp adapter requires an allocated image";
		}
		return false;
	}
	image.width = request.image.width;
	image.height = request.image.height;
	image.channels = 3;
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

inline std::uint64_t computeImageFingerprint(const ofxGgmlSamImage & image) {
	constexpr std::uint64_t fnvOffset = 14695981039346656037ull;
	constexpr std::uint64_t fnvPrime = 1099511628211ull;
	std::uint64_t hash = fnvOffset;
	const auto mix = [&hash](std::uint64_t value) {
		for (int i = 0; i < 8; ++i) {
			hash ^= static_cast<unsigned char>((value >> (i * 8)) & 0xffu);
			hash *= fnvPrime;
		}
	};
	mix(static_cast<std::uint64_t>(image.width));
	mix(static_cast<std::uint64_t>(image.height));
	mix(static_cast<std::uint64_t>(image.channels));
	mix(static_cast<std::uint64_t>(image.pixels.size()));
	for (const auto value : image.pixels) {
		hash ^= value;
		hash *= fnvPrime;
	}
	return hash;
}

template <typename Values>
inline void copyMaskValues(const Values & source, ofxGgmlSamMask & mask) {
	mask.values.reserve(source.size());
	for (const auto value : source) {
		const float numericValue = static_cast<float>(value);
		mask.values.push_back(std::clamp(
			numericValue > 1.0f ? numericValue / 255.0f : numericValue,
			0.0f,
			1.0f));
	}
}

inline ofxGgmlSamResult segmentWithRuntime(
	const std::shared_ptr<Runtime> & runtime,
	const ofxGgmlSamRequest & request) {
	ofxGgmlSamResult result;
	result.backendName = "sam3.cpp";
	result.imagePath = request.imagePath;
	if (!runtime || !runtime->model || !runtime->state) {
		result.errorMessage = "sam3.cpp runtime is not loaded";
		return result;
	}
	if (request.refinementMask.isAllocated()) {
		result.errorMessage =
			"sam3.cpp adapter mask refinement is not wired yet; use the external adapter for refinement masks";
		return result;
	}
	if (request.points.empty() && request.boxes.empty()) {
		result.errorMessage = "sam3.cpp adapter requires at least one point or box prompt";
		return result;
	}
	if (request.boxes.size() > 1) {
		result.errorMessage =
			"sam3.cpp adapter currently supports one box prompt per request";
		return result;
	}
	if (!request.boxes.empty() && !request.boxes.front().positive) {
		result.errorMessage =
			"sam3.cpp adapter currently supports positive box prompts only";
		return result;
	}

	const auto started = std::chrono::steady_clock::now();
	const auto imageFingerprint = computeImageFingerprint(request.image);
	const bool imageCacheHit =
		runtime->hasCachedImage &&
		runtime->cachedImageFingerprint == imageFingerprint;
	if (!imageCacheHit) {
		sam3_image image;
		if (!fillSam3Image(request, image, &result.errorMessage)) {
			return result;
		}
		if (!sam3_encode_image(*runtime->state, *runtime->model, image)) {
			result.errorMessage = "sam3.cpp failed to encode image";
			runtime->hasCachedImage = false;
			return result;
		}
		runtime->cachedImageFingerprint = imageFingerprint;
		runtime->hasCachedImage = true;
	}

	sam3_pvs_params pvs;
	pvs.multimask = request.returnMultipleMasks;
	for (const auto & point : request.points) {
		const sam3_point samPoint {
			std::clamp(point.x, 0.0f, 1.0f) *
				static_cast<float>(request.image.width),
			std::clamp(point.y, 0.0f, 1.0f) *
				static_cast<float>(request.image.height)
		};
		if (point.positive) {
			pvs.pos_points.push_back(samPoint);
		} else {
			pvs.neg_points.push_back(samPoint);
		}
	}
	if (!request.boxes.empty()) {
		const auto & box = request.boxes.front();
		pvs.box = {
			std::clamp(box.x0, 0.0f, 1.0f) *
				static_cast<float>(request.image.width),
			std::clamp(box.y0, 0.0f, 1.0f) *
				static_cast<float>(request.image.height),
			std::clamp(box.x1, 0.0f, 1.0f) *
				static_cast<float>(request.image.width),
			std::clamp(box.y1, 0.0f, 1.0f) *
				static_cast<float>(request.image.height)
		};
		pvs.use_box = true;
	}

	const sam3_result samResult =
		sam3_segment_pvs(*runtime->state, *runtime->model, pvs);
	if (samResult.detections.empty()) {
		result.errorMessage = "sam3.cpp did not produce any masks";
		return result;
	}

	const size_t maskCount = request.returnMultipleMasks
		? samResult.detections.size()
		: 1u;
	for (size_t i = 0; i < maskCount; ++i) {
		const auto & detection = samResult.detections[i];
		const auto & samMask = detection.mask;
		if (samMask.width <= 0 || samMask.height <= 0 || samMask.data.empty()) {
			continue;
		}

		ofxGgmlSamMask mask;
		mask.width = samMask.width;
		mask.height = samMask.height;
		mask.score = samMask.iou_score;
		copyMaskValues(samMask.data, mask);
		result.masks.push_back(std::move(mask));
	}

	if (result.masks.empty()) {
		result.errorMessage = "sam3.cpp produced detections without usable masks";
		return result;
	}

	result.success = true;
	result.elapsedMs = std::chrono::duration<float, std::milli>(
		std::chrono::steady_clock::now() - started).count();
	result.metadata.push_back({ "backend", "sam3.cpp" });
	result.metadata.push_back({ "threads", std::to_string(runtime->params.n_threads) });
	result.metadata.push_back({ "useGpu", runtime->params.use_gpu ? "true" : "false" });
	result.metadata.push_back({ "imageCache", imageCacheHit ? "hit" : "miss" });
	result.metadata.push_back({ "boxPrompt", pvs.use_box ? "true" : "false" });
	result.metadata.push_back({ "modelPath", runtime->modelPath });
	return result;
}

inline std::shared_ptr<ofxGgmlSamBackend> createBackend(
	std::shared_ptr<Runtime> runtime,
	const std::string & displayName = "sam3.cpp") {
	auto mutex = std::make_shared<std::mutex>();
	return ofxGgmlSamInference::createBridgeBackend(
		[runtime, mutex](const ofxGgmlSamRequest & request) {
			std::lock_guard<std::mutex> lock(*mutex);
			return segmentWithRuntime(runtime, request);
		},
		displayName);
}

inline std::shared_ptr<ofxGgmlSamBackend> createBackend(
	const std::string & modelPath,
	const RuntimeOptions & options = {},
	const std::string & displayName = "sam3.cpp") {
	std::string error;
	auto runtime = loadRuntime(modelPath, options, &error);
	if (!runtime) {
		return ofxGgmlSamInference::createBridgeBackend(
			[error, modelPath](const ofxGgmlSamRequest & request) {
				ofxGgmlSamResult result;
				result.backendName = "sam3.cpp";
				result.imagePath = request.imagePath;
				result.errorMessage = error.empty()
					? "failed to load sam3.cpp model: " + modelPath
					: error;
				return result;
			},
			displayName);
	}
	return createBackend(std::move(runtime), displayName);
}

inline void attachBackend(
	ofxGgmlSamInference & inference,
	const std::string & modelPath,
	const RuntimeOptions & options = {},
	const std::string & displayName = "sam3.cpp") {
	inference.setBackend(createBackend(modelPath, options, displayName));
}

#else

inline std::shared_ptr<ofxGgmlSamBackend> createBackend(
	const std::string & modelPath,
	const RuntimeOptions & = {},
	const std::string & displayName = "sam3.cpp") {
	return ofxGgmlSamInference::createBridgeBackend(
		[modelPath](const ofxGgmlSamRequest & request) {
			ofxGgmlSamResult result;
			result.backendName = "sam3.cpp";
			result.imagePath = request.imagePath;
			result.errorMessage =
				"sam3.cpp adapter is disabled. Define OFXGGML_ENABLE_SAM3_ADAPTER, "
				"add sam3.cpp headers, and link sam3.lib before using model: " + modelPath;
			return result;
		},
		displayName);
}

inline void attachBackend(
	ofxGgmlSamInference & inference,
	const std::string & modelPath,
	const RuntimeOptions & options = {},
	const std::string & displayName = "sam3.cpp") {
	inference.setBackend(createBackend(modelPath, options, displayName));
}

#endif

} // namespace ofxGgmlSam3Adapters
