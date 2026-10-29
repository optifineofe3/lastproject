ARCHS = arm64 arm64e
TARGET = iphone:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Tweak

$(TWEAK_NAME)_FILES = $(shell find Sources \( -name '*.swift' -o -name '*.m' -o -name '*.xm' -o -name '*.c' \))
$(TWEAK_NAME)_SWIFTFLAGS = -ISources/tgapiC/include
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -ISources/tgapiC/include -Wno-deprecated-declarations
$(TWEAK_NAME)_FRAMEWORKS = CoreServices UIKit CoreLocation QuartzCore Security
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal
$(TWEAK_NAME)_RESOURCE_FILES = Sources/tgapi/Resources

Sources/tgapi/fishhook/fishhook.c_CFLAGS = -fno-objc-arc

# Copy Tweak.bundle manually during the packaging step
after-stage::
	@echo ">>> Copying Tweak.bundle into .deb package..."
	@mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support/Tweak
	@cp -a Tweak.bundle $(THEOS_STAGING_DIR)/Library/Application\ Support/Tweak

include $(THEOS_MAKE_PATH)/tweak.mk
