include ShijianTokenBalanceBuild.mk

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ShijianTokenBalance
ShijianTokenBalance_FILES = Tweak.xm
ShijianTokenBalance_CFLAGS = -fobjc-arc -Wall -Wextra -DAPELIN_BUILD_ID=\"$(APELIN_BUILD_ID)\"
ShijianTokenBalance_FRAMEWORKS = UIKit Foundation
ShijianTokenBalance_LIBRARIES = roothide

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += ShijianTokenBalancePrefs
SUBPROJECTS += ShijianTokenBalanceCC
include $(THEOS_MAKE_PATH)/aggregate.mk
