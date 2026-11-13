include ../ShijianTokenBalanceBuild.mk
export ARCHS := arm64 arm64e
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ShijianTokenBalanceCC
ShijianTokenBalanceCC_FILES = ShijianTokenBalanceCCModule.m
ShijianTokenBalanceCC_CFLAGS = -fobjc-arc -Wall -Wextra
ShijianTokenBalanceCC_FRAMEWORKS = UIKit Foundation
ShijianTokenBalanceCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit
ShijianTokenBalanceCC_LIBRARIES = roothide
ShijianTokenBalanceCC_INSTALL_PATH = /Library/ControlCenter/Bundles

include $(THEOS_MAKE_PATH)/bundle.mk
