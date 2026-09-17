# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause

include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

PACKAGE_NAME = Kaleidoscope
VERSION = 1

# The scheme model lives in a library, not in each bundle. The theme and the
# preference pane are loaded into one process together, and a class compiled
# into both of them is loaded twice - which the runtime resolves by picking one
# of the two, undefined which. That is a real bug and it bit: the pane called a
# method the theme's older copy of the class did not have.
LIBRARY_NAME = libKaleidoscopeScheme
libKaleidoscopeScheme_INTERFACE_VERSION = 1
libKaleidoscopeScheme_OBJC_FILES = \
		KGarden.m\
		KIconDecoder.m\
		KResourceFork.m\
		KScheme.m\
		KSchemeStore.m
libKaleidoscopeScheme_HEADER_FILES = \
		KGarden.h\
		KIconDecoder.h\
		KResourceFork.h\
		KScheme.h\
		KSchemeStore.h
libKaleidoscopeScheme_HEADER_FILES_INSTALL_DIR = KaleidoscopeScheme

BUNDLE_NAME = Kaleidoscope
BUNDLE_EXTENSION = .theme
Kaleidoscope_INSTALL_DIR = $(GNUSTEP_LIBRARY)/Themes
Kaleidoscope_PRINCIPAL_CLASS = Kaleidoscope
Kaleidoscope_OBJC_FILES = \
		Kaleidoscope.m\
		KaleidoscopeScrollerCells.m
Kaleidoscope_BUNDLE_LIBS = -lKaleidoscopeScheme

ADDITIONAL_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)
ADDITIONAL_OBJCFLAGS += -Wall

include $(GNUSTEP_MAKEFILES)/library.make
include $(GNUSTEP_MAKEFILES)/bundle.make
