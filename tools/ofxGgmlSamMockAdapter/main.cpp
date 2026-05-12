#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>

namespace {
	struct Options {
		std::string imagePath;
		std::string outputPath;
		float pointX = 0.5f;
		float pointY = 0.5f;
		bool positive = true;
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
		const float cx = options.pointX * static_cast<float>(std::max(1, width - 1));
		const float cy = options.pointY * static_cast<float>(std::max(1, height - 1));
		const float radius = std::max(2.0f, std::min(width, height) * 0.25f);
		for (int y = 0; y < height; ++y) {
			for (int x = 0; x < width; ++x) {
				const float dx = static_cast<float>(x) - cx;
				const float dy = static_cast<float>(y) - cy;
				const float distance = std::sqrt(dx * dx + dy * dy);
				float value = std::max(0.0f, 1.0f - distance / radius);
				if (!options.positive) {
					value = 1.0f - value;
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
				options.pointX = std::stof(next());
			} else if (key == "--point-y") {
				options.pointY = std::stof(next());
			} else if (key == "--point-label") {
				options.positive = next() != "negative";
			} else if (key == "--model") {
				(void)next();
			} else {
				(void)key;
			}
		}
		options.pointX = std::clamp(options.pointX, 0.0f, 1.0f);
		options.pointY = std::clamp(options.pointY, 0.0f, 1.0f);
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
