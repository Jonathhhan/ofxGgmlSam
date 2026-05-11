meta:
	ADDON_NAME = ofxGgmlSam
	ADDON_DESCRIPTION = Companion addon for SAM/SAM2/SAM3 segmentation workflows on top of ofxGgml
	ADDON_AUTHOR = Jonathan Frank
	ADDON_TAGS = "ggml,ai,sam,segmentation,vision"
	ADDON_URL = https://github.com/Jonathhhan/ofxGgmlSam

common:
	ADDON_DEPENDENCIES += ofxGgml
	ADDON_INCLUDES += src
	ADDON_SOURCES_EXCLUDE += build/%
	ADDON_SOURCES_EXCLUDE += libs/*/build/%
	ADDON_SOURCES_EXCLUDE += libs/*/build*/%
	ADDON_INCLUDES_EXCLUDE += build/%
	ADDON_INCLUDES_EXCLUDE += libs/*/build/%
	ADDON_INCLUDES_EXCLUDE += libs/*/build*/%
