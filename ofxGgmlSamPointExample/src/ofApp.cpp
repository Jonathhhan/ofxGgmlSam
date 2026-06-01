#include "ofApp.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {
	constexpr const char * LogModule = "ofxGgmlSamPointExample";
	constexpr const char * kBackendLabels[] = {
		"sam3.cpp",
		"sam.cpp"
	};
	constexpr const char * kPromptLabels[] = {
		"Point",
		"Box"
	};

	std::string getEnvString(const std::string & name) {
		const auto value = std::getenv(name.c_str());
		return value ? std::string(value) : "";
	}

	std::string toLower(std::string value) {
		std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
			return static_cast<char>(std::tolower(c));
		});
		return value;
	}

	std::string trim(const std::string & value) {
		const auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char c) {
			return std::isspace(c) != 0;
		});
		const auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char c) {
			return std::isspace(c) != 0;
		}).base();
		if (first >= last) {
			return "";
		}
		return std::string(first, last);
	}

	std::string normalizeUserPath(const std::string & value) {
		std::string path = trim(value);
		if (path.size() >= 2) {
			const char first = path.front();
			const char last = path.back();
			if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
				path = trim(path.substr(1, path.size() - 2));
			}
		}
		return path;
	}

	bool fileExists(const std::string & path) {
		return !path.empty() && ofFile(path).exists();
	}

	bool hasExtension(const std::string & path, const std::vector<std::string> & extensions) {
		const auto extension = toLower(ofFilePath::getFileExt(path));
		return std::find(extensions.begin(), extensions.end(), extension) != extensions.end();
	}

	void appendExistingModelFiles(
		std::vector<std::string> & paths,
		const std::string & directoryPath,
		const std::vector<std::string> & extensions) {
		ofDirectory directory(directoryPath);
		if (!directory.exists()) {
			return;
		}
		directory.listDir();
		directory.sort();
		for (const auto & entry : directory.getFiles()) {
			const auto path = entry.getAbsolutePath();
			if (entry.isFile() && hasExtension(path, extensions)) {
				paths.push_back(path);
			}
		}
	}

	void copyToBuffer(const std::string & text, char * buffer, std::size_t size) {
		if (size == 0) {
			return;
		}
		std::snprintf(buffer, size, "%s", text.c_str());
	}

	std::string chooseFile(const std::string & title, const std::string & currentPath) {
		const auto normalizedPath = normalizeUserPath(currentPath);
		const auto startPath = normalizedPath.empty()
			? ofToDataPath("", true)
			: normalizedPath;
		auto result = ofSystemLoadDialog(title, false, startPath);
		return result.bSuccess ? normalizeUserPath(result.getPath()) : "";
	}

	ofxGgmlSamBox ensureVisibleBox(ofxGgmlSamBox box) {
		constexpr float minSize = 0.01f;
		if (box.x1 - box.x0 < minSize) {
			const float center = (box.x0 + box.x1) * 0.5f;
			box.x0 = ofClamp(center - minSize * 0.5f, 0.0f, 1.0f - minSize);
			box.x1 = box.x0 + minSize;
		}
		if (box.y1 - box.y0 < minSize) {
			const float center = (box.y0 + box.y1) * 0.5f;
			box.y0 = ofClamp(center - minSize * 0.5f, 0.0f, 1.0f - minSize);
			box.y1 = box.y0 + minSize;
		}
		return box;
	}
}

void ofApp::SegmentationWorker::start() {
	if (!isThreadRunning()) {
		startThread();
	}
}

void ofApp::SegmentationWorker::stop() {
	jobs.close();
	waitForThread(true);
	results.close();
}

bool ofApp::SegmentationWorker::submit(SegmentationJob job) {
	if (busy.load()) {
		return false;
	}
	busy.store(true);
	const bool sent = jobs.send(std::move(job));
	if (!sent) {
		busy.store(false);
	}
	return sent;
}

bool ofApp::SegmentationWorker::tryReceive(SegmentationJobResult & result) {
	return results.tryReceive(result);
}

bool ofApp::SegmentationWorker::isBusy() const {
	return busy.load();
}

void ofApp::SegmentationWorker::configureBackend(const SegmentationJob & job) {
	if (cachedBackendIndex == job.backendIndex && cachedModelPath == job.modelPath) {
		return;
	}

	switch (job.backendIndex) {
	case 1:
		ofxGgmlSamCppAdapters::attachBackend(inference, job.modelPath);
		break;
	case 0:
	default:
		ofxGgmlSam3Adapters::attachBackend(inference, job.modelPath);
		break;
	}
	cachedBackendIndex = job.backendIndex;
	cachedModelPath = job.modelPath;
}

void ofApp::SegmentationWorker::threadedFunction() {
	SegmentationJob job;
	while (jobs.receive(job)) {
		SegmentationJobResult completed;
		completed.id = job.id;
		completed.backendLabel = job.backendLabel;
		try {
			configureBackend(job);
			completed.result = inference.segment(job.request);
		} catch (const std::exception & error) {
			completed.result.backendName = job.backendLabel;
			completed.result.imagePath = job.request.imagePath;
			completed.result.errorMessage = std::string("segmentation worker failed: ") + error.what();
		} catch (...) {
			completed.result.backendName = job.backendLabel;
			completed.result.imagePath = job.request.imagePath;
			completed.result.errorMessage = "segmentation worker failed";
		}
		results.send(std::move(completed));
		busy.store(false);
	}
	busy.store(false);
}

void ofApp::setup() {
	ofSetWindowTitle("ofxGgmlSam point example");
	gui.setup();
	segmentationWorker.start();

	modelPath = getEnvString("OFXGGML_SAM_MODEL");
	imagePath = getEnvString("OFXGGML_SAM_IMAGE");
	const auto backend = toLower(getEnvString("OFXGGML_SAM_BACKEND"));
	if (backend == "sam.cpp" || backend == "samcpp") {
		selectedBackendIndex = 1;
	} else {
		selectedBackendIndex = 0;
	}
	modelPath = normalizeUserPath(modelPath);
	if (modelPath.empty()) {
		modelPath = findDefaultModelPath();
		if (!modelPath.empty()) {
			setStatus("auto-detected model: " + modelPath);
		}
	}

	ensurePromptDefaults();
	loadImage();
}

void ofApp::update() {
	SegmentationJobResult completed;
	while (segmentationWorker.tryReceive(completed)) {
		if (completed.id < latestSubmittedJobId) {
			continue;
		}
		lastResult = std::move(completed.result);
		if (!lastResult) {
			setStatus(lastResult.errorMessage, true);
			maskTexture.clear();
			continue;
		}
		updateMaskTexture();
		setStatus("segmentation complete");
	}
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
		ensurePromptDefaults();
		if (isBoxPromptSelected()) {
			const auto & box = request.boxes.front();
			ofNoFill();
			ofSetLineWidth(3.0f);
			ofSetColor(ofColor::limeGreen);
			ofDrawRectangle(
				imageRect.x + box.x0 * imageRect.width,
				imageRect.y + box.y0 * imageRect.height,
				(box.x1 - box.x0) * imageRect.width,
				(box.y1 - box.y0) * imageRect.height);
			ofSetLineWidth(1.0f);
			ofFill();
		} else {
			ofSetColor(request.points.front().positive ? ofColor::limeGreen : ofColor::red);
			ofDrawCircle(
				imageRect.x + request.points.front().x * imageRect.width,
				imageRect.y + request.points.front().y * imageRect.height,
				6.0f);
		}
	} else {
		ofSetColor(80);
		ofDrawRectangle(imageRect);
		ofSetColor(230);
		ofDrawBitmapString("Set OFXGGML_SAM_IMAGE or enter an image path.", imageRect.x + 16, imageRect.y + 28);
	}

	gui.begin();
	ImGui::SetNextWindowSize(ImVec2(480, 330), ImGuiCond_FirstUseEver);
	ImGui::Begin("ofxGgmlSam Point Example");

	static char modelBuffer[1024];
	static char imageBuffer[1024];
	static bool buffersInitialized = false;
	if (!buffersInitialized) {
		copyToBuffer(modelPath, modelBuffer, sizeof(modelBuffer));
		copyToBuffer(imagePath, imageBuffer, sizeof(imageBuffer));
		buffersInitialized = true;
	}

	if (ImGui::InputText("Model", modelBuffer, sizeof(modelBuffer))) {
		modelPath = modelBuffer;
	}
	if (ImGui::Button("Choose Model")) {
		const auto selectedPath = chooseFile("Choose SAM model", modelPath);
		if (!selectedPath.empty()) {
			modelPath = selectedPath;
			if (hasExtension(modelPath, { "ggml" })) {
				selectedBackendIndex = 0;
			} else if (hasExtension(modelPath, { "bin" })) {
				selectedBackendIndex = 1;
				if (isBoxPromptSelected()) {
					selectedPromptIndex = 0;
				}
			}
			copyToBuffer(modelPath, modelBuffer, sizeof(modelBuffer));
			setStatus("selected model: " + modelPath);
		}
	}
	if (ImGui::InputText("Image", imageBuffer, sizeof(imageBuffer))) {
		imagePath = imageBuffer;
	}
	if (ImGui::Button("Choose Image")) {
		const auto selectedPath = chooseFile("Choose image", imagePath);
		if (!selectedPath.empty()) {
			imagePath = selectedPath;
			copyToBuffer(imagePath, imageBuffer, sizeof(imageBuffer));
			loadImage();
		}
	}
	if (ImGui::Combo("Backend", &selectedBackendIndex, kBackendLabels, IM_ARRAYSIZE(kBackendLabels))) {
		if (selectedBackendIndex == 1 && isBoxPromptSelected()) {
			selectedPromptIndex = 0;
			ensurePromptDefaults();
			setStatus("sam.cpp path is point-prompt-only", true);
		}
		if (!isModelPathCompatibleWithBackend(modelPath)) {
			modelPath = findDefaultModelPath();
			copyToBuffer(modelPath, modelBuffer, sizeof(modelBuffer));
		}
		if (modelPath.empty()) {
			setStatus("backend selected: " + getBackendLabel() + "; no compatible model auto-detected", true);
		} else {
			setStatus("backend selected: " + getBackendLabel());
		}
	}
	if (ImGui::Combo("Prompt", &selectedPromptIndex, kPromptLabels, IM_ARRAYSIZE(kPromptLabels))) {
		ensurePromptDefaults();
		if (isBoxPromptSelected()) {
			selectedBackendIndex = 0;
			if (!isModelPathCompatibleWithBackend(modelPath)) {
				modelPath = findDefaultModelPath();
				copyToBuffer(modelPath, modelBuffer, sizeof(modelBuffer));
			}
			setStatus("box prompt selected: sam3.cpp");
		} else {
			setStatus("point prompt selected");
		}
		if (autoRun) {
			runSegmentation();
		}
	}
	if (ImGui::Button("Load Image")) {
		loadImage();
	}
	ImGui::SameLine();
	if (ImGui::Button(segmentationWorker.isBusy() ? "Running..." : "Run")) {
		runSegmentation();
	}
	ImGui::SameLine();
	ImGui::Checkbox("Auto", &autoRun);

	ensurePromptDefaults();
	bool promptChanged = false;
	if (isBoxPromptSelected()) {
		auto & box = request.boxes.front();
		promptChanged |= ImGui::SliderFloat("Box X0", &box.x0, 0.0f, 1.0f);
		promptChanged |= ImGui::SliderFloat("Box Y0", &box.y0, 0.0f, 1.0f);
		promptChanged |= ImGui::SliderFloat("Box X1", &box.x1, 0.0f, 1.0f);
		promptChanged |= ImGui::SliderFloat("Box Y1", &box.y1, 0.0f, 1.0f);
		if (promptChanged) {
			box = ensureVisibleBox(ofxGgmlSamMakeBox(box.x0, box.y0, box.x1, box.y1, true));
		}
	} else {
		auto & point = request.points.front();
		promptChanged |= ImGui::SliderFloat("Point X", &point.x, 0.0f, 1.0f);
		promptChanged |= ImGui::SliderFloat("Point Y", &point.y, 0.0f, 1.0f);
		promptChanged |= ImGui::Checkbox("Positive", &point.positive);
	}
	if (promptChanged && autoRun) {
		runSegmentation();
	}

	ImGui::Separator();
	ImGui::TextWrapped("Backend: %s", getBackendLabel().c_str());
	ImGui::TextWrapped("Result backend: %s", lastResult.backendName.empty() ? "(none)" : lastResult.backendName.c_str());
	ImGui::TextWrapped("Status: %s", status.c_str());
	if (lastResult) {
		ImGui::Text("Time: %.1f ms", lastResult.elapsedMs);
		ImGui::Text("Masks: %d", static_cast<int>(lastResult.masks.size()));
		if (!lastResult.masks.empty()) {
			ImGui::Text("Score: %.3f", lastResult.masks.front().score);
		}
	}
	ImGui::End();
	gui.end();
}

void ofApp::exit() {
	segmentationWorker.stop();
}

void ofApp::mousePressed(int x, int y, int button) {
	if (button != OF_MOUSE_BUTTON_LEFT || !imageLoaded) {
		return;
	}
	const auto imageRect = getImageRect();
	if (!imageRect.inside(x, y)) {
		return;
	}
	ensurePromptDefaults();
	const auto normalized = getNormalizedImagePoint(x, y);
	if (isBoxPromptSelected()) {
		draggingBox = true;
		boxDragStart = normalized;
		setBoxFromCorners(boxDragStart, normalized);
	} else {
		request.points.front() = ofxGgmlSamMakePoint(normalized.x, normalized.y, true);
	}
	if (autoRun && !isBoxPromptSelected()) {
		runSegmentation();
	}
}

void ofApp::mouseDragged(int x, int y, int button) {
	if (button != OF_MOUSE_BUTTON_LEFT || !draggingBox || !imageLoaded || !isBoxPromptSelected()) {
		return;
	}
	setBoxFromCorners(boxDragStart, getNormalizedImagePoint(x, y));
}

void ofApp::mouseReleased(int x, int y, int button) {
	if (button != OF_MOUSE_BUTTON_LEFT || !draggingBox || !isBoxPromptSelected()) {
		return;
	}
	draggingBox = false;
	setBoxFromCorners(boxDragStart, getNormalizedImagePoint(x, y));
	if (autoRun) {
		runSegmentation();
	}
}

void ofApp::loadImage() {
	maskTexture.clear();
	lastResult = {};
	imageLoaded = false;
	imagePath = normalizeUserPath(imagePath);

	if (!imagePath.empty()) {
		if (loadImageFromPath(imagePath)) {
			return;
		}
		setStatus("could not load image: " + imagePath, true);
		return;
	}

	const std::string defaultImagePath = ofToDataPath("OIkametanjo.jpg", true);
	if (loadImageFromPath(defaultImagePath)) {
		imagePath = defaultImagePath;
		setStatus("default image loaded");
		return;
	}

	loadGeneratedImage();
	setStatus("generated fallback image");
}

bool ofApp::loadImageFromPath(const std::string & path) {
	if (path.empty() || !image.load(path)) {
		return false;
	}
	imageLoaded = true;
	updateRequestImage();
	setStatus("image loaded");
	return true;
}

void ofApp::loadGeneratedImage() {
	ofPixels pixels;
	pixels.allocate(512, 384, OF_PIXELS_RGB);
	for (int y = 0; y < pixels.getHeight(); ++y) {
		for (int x = 0; x < pixels.getWidth(); ++x) {
			const float nx = static_cast<float>(x) / static_cast<float>(pixels.getWidth() - 1);
			const float ny = static_cast<float>(y) / static_cast<float>(pixels.getHeight() - 1);
			const unsigned char r = static_cast<unsigned char>(40 + nx * 120);
			const unsigned char g = static_cast<unsigned char>(70 + ny * 130);
			const unsigned char b = static_cast<unsigned char>(120 + (1.0f - nx) * 80);
			pixels.setColor(x, y, ofColor(r, g, b));
		}
	}

	const ofVec2f center(pixels.getWidth() * 0.48f, pixels.getHeight() * 0.52f);
	const float radius = std::min(pixels.getWidth(), pixels.getHeight()) * 0.23f;
	for (int y = 0; y < pixels.getHeight(); ++y) {
		for (int x = 0; x < pixels.getWidth(); ++x) {
			const float distance = center.distance(ofVec2f(static_cast<float>(x), static_cast<float>(y)));
			if (distance < radius) {
				const float t = 1.0f - distance / radius;
				pixels.setColor(x, y, ofColor(
					static_cast<unsigned char>(220 * t + 80 * (1.0f - t)),
					static_cast<unsigned char>(190 * t + 70 * (1.0f - t)),
					static_cast<unsigned char>(70 * t + 140 * (1.0f - t))));
			}
		}
	}

	if (!image.getPixels().isAllocated()) {
		image.allocate(pixels.getWidth(), pixels.getHeight(), OF_IMAGE_COLOR);
	}
	image.setFromPixels(pixels);
	image.update();
	imageLoaded = true;
	updateRequestImage();
	ensurePromptDefaults();
	request.points.front() = ofxGgmlSamMakePoint(0.48f, 0.52f, true);
	request.boxes.front() = ensureVisibleBox(ofxGgmlSamMakeBox(0.25f, 0.25f, 0.75f, 0.75f, true));
}

std::string ofApp::findDefaultModelPath() const {
	const auto dataRoot = ofToDataPath("", true);
	const auto addonRoot = ofFilePath::getAbsolutePath(ofFilePath::join(dataRoot, "../../.."));
	const auto backend = getBackendLabel();
	const std::vector<std::string> extensions = backend == "sam.cpp"
		? std::vector<std::string>{ "bin" }
		: std::vector<std::string>{ "ggml" };
	const std::vector<std::string> directories = {
		dataRoot,
		ofFilePath::join(dataRoot, "models"),
		ofFilePath::join(addonRoot, "models"),
		ofFilePath::join(addonRoot, "libs/sam3.cpp/source/models"),
		ofFilePath::join(addonRoot, "libs/sam.cpp/source/checkpoints"),
		ofFilePath::join(addonRoot, "libs/sam.cpp/source/models"),
		ofFilePath::join(addonRoot, "libs/sam.cpp/source/models/sam-vit-b")
	};

	std::vector<std::string> candidates;
	for (const auto & directory : directories) {
		appendExistingModelFiles(candidates, directory, extensions);
	}
	if (candidates.empty()) {
		return "";
	}
	return candidates.front();
}

std::string ofApp::getBackendLabel() const {
	if (selectedBackendIndex >= 0 &&
		selectedBackendIndex < static_cast<int>(IM_ARRAYSIZE(kBackendLabels))) {
		return kBackendLabels[selectedBackendIndex];
	}
	return kBackendLabels[0];
}

bool ofApp::isModelPathCompatibleWithBackend(const std::string & path) const {
	if (path.empty()) {
		return false;
	}
	const auto backend = getBackendLabel();
	if (backend == "sam.cpp") {
		return hasExtension(path, { "bin" });
	}
	return hasExtension(path, { "ggml" });
}

bool ofApp::ensureModelPath() {
	modelPath = normalizeUserPath(modelPath);
	if (modelPath.empty() || !isModelPathCompatibleWithBackend(modelPath)) {
		modelPath = findDefaultModelPath();
	}
	if (modelPath.empty()) {
		setStatus(
			"model missing for " + getBackendLabel() +
				"; set OFXGGML_SAM_MODEL or put a model in bin/data/models",
			true);
		maskTexture.clear();
		lastResult = {};
		return false;
	}
	if (!fileExists(modelPath)) {
		setStatus("model not found: " + modelPath, true);
		maskTexture.clear();
		lastResult = {};
		return false;
	}
	return true;
}

void ofApp::runSegmentation() {
	if (segmentationWorker.isBusy()) {
		setStatus("segmentation already running");
		return;
	}
	if (!imageLoaded) {
		setStatus("load an image first", true);
		return;
	}
	if (!ensureModelPath()) {
		return;
	}
	ensurePromptDefaults();
	if (isBoxPromptSelected() && selectedBackendIndex != 0) {
		setStatus("box prompts require sam3.cpp", true);
		return;
	}
	updateRequestImage();
	request.modelPath = modelPath;
	request.imagePath = imagePath.empty() ? "generated-fallback" : imagePath;
	request.external.executablePath.clear();
	if (isBoxPromptSelected()) {
		request.points.clear();
		request.boxes.resize(1);
	} else {
		request.boxes.clear();
		request.points.resize(1);
	}

	SegmentationJob job;
	job.request = request;
	job.modelPath = modelPath;
	job.backendLabel = getBackendLabel();
	job.backendIndex = selectedBackendIndex;
	job.id = nextJobId++;
	const auto submittedJobId = job.id;
	if (!segmentationWorker.submit(std::move(job))) {
		setStatus("segmentation already running");
		return;
	}
	latestSubmittedJobId = submittedJobId;
	setStatus("segmentation running");
}

void ofApp::ensurePromptDefaults() {
	if (request.points.empty()) {
		request.points.push_back(ofxGgmlSamMakePoint(0.5f, 0.5f, true));
	}
	if (request.boxes.empty()) {
		request.boxes.push_back(ensureVisibleBox(ofxGgmlSamMakeBox(0.25f, 0.25f, 0.75f, 0.75f, true)));
	}
}

bool ofApp::isBoxPromptSelected() const {
	return selectedPromptIndex == 1;
}

ofVec2f ofApp::getNormalizedImagePoint(int x, int y) const {
	const auto imageRect = getImageRect();
	return {
		ofClamp((static_cast<float>(x) - imageRect.x) / imageRect.width, 0.0f, 1.0f),
		ofClamp((static_cast<float>(y) - imageRect.y) / imageRect.height, 0.0f, 1.0f)
	};
}

void ofApp::setBoxFromCorners(const ofVec2f & a, const ofVec2f & b) {
	ensurePromptDefaults();
	request.boxes.front() = ensureVisibleBox(ofxGgmlSamMakeBox(a.x, a.y, b.x, b.y, true));
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
