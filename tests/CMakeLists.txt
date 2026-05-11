cmake_minimum_required(VERSION 3.18)
project(ofxGgmlSam_tests CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(ofxGgmlSam_tests
	test_main.cpp
	../src/ofxGgmlSam/ofxGgmlSamInference.cpp
	../src/ofxGgmlSam/ofxGgmlSamUtils.cpp)

target_include_directories(ofxGgmlSam_tests PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/../src)

enable_testing()
add_test(NAME ofxGgmlSam_tests COMMAND ofxGgmlSam_tests)
