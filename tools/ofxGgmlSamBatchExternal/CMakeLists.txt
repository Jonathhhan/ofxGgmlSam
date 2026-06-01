cmake_minimum_required(VERSION 3.18)
project(ofxGgmlSamBatchExternal CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(OFX_GGML_CORE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../ofxGgmlCore")
set(OFX_GGML_SAM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

add_executable(ofxGgmlSamBatchExternal
	main.cpp
	${OFX_GGML_SAM_ROOT}/src/ofxGgmlSam/ofxGgmlSamExternalBackend.cpp
	${OFX_GGML_SAM_ROOT}/src/ofxGgmlSam/ofxGgmlSamInference.cpp
	${OFX_GGML_SAM_ROOT}/src/ofxGgmlSam/ofxGgmlSamUtils.cpp)

target_include_directories(ofxGgmlSamBatchExternal PRIVATE
	${OFX_GGML_SAM_ROOT}/src
	${OFX_GGML_CORE_ROOT}/src)
