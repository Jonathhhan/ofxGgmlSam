#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {
	struct Options {
		std::string imagePath;
		std::string outputPath;
		std::vector<float> pointXs;
		std::vector<float> pointYs;
		std::vector<bool> positives;
	};

	std::string readToken(std::istream & input) {
		std::string token;
		char c = 0;
		while (input.get(c)) {
			if (std::isspace(static_cast<unsigned char>(c))) {
				continue;
			}
			if (c == '#') {
				std::string comment;
				std::getline(input, comment);
				continue;
			}
			token.push_back(c);
			break;
		}
		while (input.get(c)) {
			if (std::isspace(static_cast<unsigned char>(c))) {
				break;
			}
			token.push_back(c);
		}
		return token;
	}

	bool readPpmSize(const std::string & path, int & width, int & height) {
		std::ifstream input(path, std::ios::binary);
		if (!input) {
			return false;
		}
		const auto magic = readToken(input);
		if (magic != "P6" && magic != "P3") {
			return false;
		}
		width = std::stoi(readToken(input));
		height = std::stoi(readToken(input));
		const auto maxValue = std::stoi(readToken(input));
		return width > 0 && height > 0 && maxValue > 0;
	}

	bool writeMask(const Options & options, int width, int height) {
		std::ofstream output(options.outputPath, std::ios::binary);
		if (!output) {
			return false;
		}
		output << "P5\n" << width << " " << height << "\n255\n";
		const float radius = std::max(2.0f, std::min(width, height) * 0.25f);
		for (int y = 0; y < height; ++y) {
			for (int x = 0; x < width; ++x) {
				float value = 0.0f;
				for (std::size_t i = 0; i < options.pointXs.size(); ++i) {
					const float cx = options.pointXs[i] * static_cast<float>(std::max(1, width - 1));
					const float cy = options.pointYs[i] * static_cast<float>(std::max(1, height - 1));
					const float dx = static_cast<float>(x) - cx;
					const float dy = static_cast<float>(y) - cy;
					const float distance = std::sqrt(dx * dx + dy * dy);
					const float influence = std::max(0.0f, 1.0f - distance / radius);
					if (options.positives[i]) {
						value = std::max(value, influence);
					} else {
						value *= 1.0f - influence;
					}
				}
				output.put(static_cast<char>(std::clamp(value, 0.0f, 1.0f) * 255.0f));
			}
		}
		return static_cast<bool>(output);
	}

	Options parseOptions(int argc, char ** argv) {
		Options options;
		for (int i = 1; i < argc; ++i) {
			const std::string key = argv[i];
			const auto next = [&]() -> std::string {
				if (i + 1 >= argc) {
					return "";
				}
				return argv[++i];
			};
			if (key == "--image") {
				options.imagePath = next();
			} else if (key == "--output") {
				options.outputPath = next();
			} else if (key == "--point-x") {
				options.pointXs.push_back(std::stof(next()));
			} else if (key == "--point-y") {
				options.pointYs.push_back(std::stof(next()));
			} else if (key == "--point-label") {
				options.positives.push_back(next() != "negative");
			} else if (key == "--model") {
				(void)next();
			} else {
				(void)key;
			}
		}
		const auto pointCount = std::min(options.pointXs.size(), options.pointYs.size());
		options.pointXs.resize(pointCount);
		options.pointYs.resize(pointCount);
		options.positives.resize(pointCount, true);
		for (auto & pointX : options.pointXs) {
			pointX = std::clamp(pointX, 0.0f, 1.0f);
		}
		for (auto & pointY : options.pointYs) {
			pointY = std::clamp(pointY, 0.0f, 1.0f);
		}
		if (options.pointXs.empty()) {
			options.pointXs.push_back(0.5f);
			options.pointYs.push_back(0.5f);
			options.positives.push_back(true);
		}
		return options;
	}
}

int main(int argc, char ** argv) {
	const auto options = parseOptions(argc, argv);
	if (options.imagePath.empty() || options.outputPath.empty()) {
		std::cerr << "usage: ofxGgmlSamMockAdapter --image image.ppm --output mask.pgm --point-x 0.5 --point-y 0.5\n";
		return 2;
	}
	int width = 0;
	int height = 0;
	if (!readPpmSize(options.imagePath, width, height)) {
		std::cerr << "could not read input PPM image: " << options.imagePath << "\n";
		return 1;
	}
	if (!writeMask(options, width, height)) {
		std::cerr << "could not write output PGM mask: " << options.outputPath << "\n";
		return 1;
	}
	return 0;
}
