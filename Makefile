ARCHS := arm64
TARGET := iphone:clang:16.5:26.0
INSTALL_TARGET_PROCESSES := RCall

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := RCall

RCall_FILES := $(wildcard Sources/*.swift)
RCall_FRAMEWORKS := UIKit Foundation AVFoundation CoreMedia ImageIO Network
RCall_EXTRA_FRAMEWORKS := WebRTC
RCall_RESOURCE_DIRS := Resources
RCall_INSTALL_PATH := /Applications
RCall_SWIFTFLAGS := -parse-as-library -F$(THEOS_PROJECT_DIR)/Frameworks
RCall_LDFLAGS := -F$(THEOS_PROJECT_DIR)/Frameworks -rpath @executable_path/Frameworks
RCall_CODESIGN_FLAGS := -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

after-RCall-all::
	@mkdir -p "$(_THEOS_SHARED_BUNDLE_BUILD_PATH)/Frameworks"
	@rsync -a "$(THEOS_PROJECT_DIR)/Frameworks/WebRTC.framework" "$(_THEOS_SHARED_BUNDLE_BUILD_PATH)/Frameworks/"
	@ldid -S "$(_THEOS_SHARED_BUNDLE_BUILD_PATH)/Frameworks/WebRTC.framework/WebRTC"
