#pragma once

#define OFXGGML_SAM_VERSION_MAJOR 1
#define OFXGGML_SAM_VERSION_MINOR 0
#define OFXGGML_SAM_VERSION_PATCH 1
#define OFXGGML_SAM_VERSION_STRING "1.0.1"

inline const char * ofxGgmlSamGetVersionString() {
	return OFXGGML_SAM_VERSION_STRING;
}
