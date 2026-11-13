include ../ShijianTokenBalanceBuild.mk
export ARCHS := arm64 arm64e
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ShijianTokenBalancePrefs
ShijianTokenBalancePrefs_FILES = ShijianTokenBalanceRootListController.m
ShijianTokenBalancePrefs_CFLAGS = -fobjc-arc -Wall -Wextra -F$(THEOS)/lib/iphone/rootless
ShijianTokenBalancePrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
ShijianTokenBalancePrefs_PRIVATE_FRAMEWORKS = Preferences
ShijianTokenBalancePrefs_LDFLAGS = -F$(THEOS)/lib/iphone/rootless -Wl,-rpath,@loader_path/../../Frameworks
ShijianTokenBalancePrefs_LIBRARIES = roothide
ShijianTokenBalancePrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
