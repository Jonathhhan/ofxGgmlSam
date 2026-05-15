cmake_minimum_required(VERSION 3.18)

project(ofxGgmlSam3RuntimeSmoke LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

get_filename_component(OFXGGMLSAM_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(SAM3_PACKAGE_DIR "${OFXGGMLSAM_ROOT}/libs/sam3.cpp")
set(SAM3_INCLUDE_DIR "${SAM3_PACKAGE_DIR}/include")
set(SAM3_LIB_DIR "${SAM3_PACKAGE_DIR}/lib/vs/x64")

if(NOT EXISTS "${SAM3_INCLUDE_DIR}/sam3.h")
	message(FATAL_ERROR "sam3.h was not found. Run scripts/install-sam3-cpp.bat first.")
endif()

foreach(required_lib sam3 ggml ggml-base ggml-cpu)
	if(NOT EXISTS "${SAM3_LIB_DIR}/${required_lib}.lib")
		message(FATAL_ERROR "${required_lib}.lib was not found. Run scripts/build-sam3-cpp.bat first.")
	endif()
	list(APPEND OFXGGMLSAM3_RUNTIME_LIBS "${SAM3_LIB_DIR}/${required_lib}.lib")
endforeach()

if(EXISTS "${SAM3_LIB_DIR}/ggml-cuda.lib")
	list(APPEND OFXGGMLSAM3_RUNTIME_LIBS "${SAM3_LIB_DIR}/ggml-cuda.lib")
endif()

add_executable(ofxGgmlSam3RuntimeSmoke main.cpp)
target_include_directories(ofxGgmlSam3RuntimeSmoke PRIVATE "${SAM3_INCLUDE_DIR}")
target_link_libraries(ofxGgmlSam3RuntimeSmoke PRIVATE ${OFXGGMLSAM3_RUNTIME_LIBS})

if(WIN32)
	target_compile_definitions(ofxGgmlSam3RuntimeSmoke PRIVATE NOMINMAX)
	target_link_libraries(ofxGgmlSam3RuntimeSmoke PRIVATE ws2_32)

	if(EXISTS "${SAM3_LIB_DIR}/ggml-cuda.lib" AND DEFINED ENV{CUDA_PATH})
		set(CUDA_LIB_DIR "$ENV{CUDA_PATH}/lib/x64")
		foreach(cuda_lib cudart cublas cuda)
			if(EXISTS "${CUDA_LIB_DIR}/${cuda_lib}.lib")
				target_link_libraries(ofxGgmlSam3RuntimeSmoke PRIVATE "${CUDA_LIB_DIR}/${cuda_lib}.lib")
			endif()
		endforeach()
	endif()
endif()
