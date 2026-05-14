meta:
	ADDON_NAME = ofxGgmlSam
	ADDON_DESCRIPTION = Companion addon for SAM/SAM2/SAM3 segmentation workflows on top of ofxGgmlCore
	ADDON_AUTHOR = Jonathan Frank
	ADDON_TAGS = "ggml,ai,sam,segmentation,vision"
	ADDON_URL = https://github.com/Jonathhhan/ofxGgmlSam

common:
	ADDON_DEPENDENCIES += ofxGgmlCore
	ADDON_INCLUDES = src
	ADDON_SOURCES = src/ofxGgmlSam/ofxGgmlSamExternalBackend.cpp
	ADDON_SOURCES += src/ofxGgmlSam/ofxGgmlSamInference.cpp
	ADDON_SOURCES += src/ofxGgmlSam/ofxGgmlSamUtils.cpp
