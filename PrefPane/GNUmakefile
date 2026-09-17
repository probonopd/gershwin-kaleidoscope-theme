# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause

include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

BUNDLE_NAME = Kaleidoscope
BUNDLE_EXTENSION = .prefPane
Kaleidoscope_PRINCIPAL_CLASS = KaleidoscopePrefPane

Kaleidoscope_OBJC_FILES = KaleidoscopePrefPane.m

Kaleidoscope_BUNDLE_LIBS = -lPreferencePanes -lKaleidoscopeScheme
ADDITIONAL_INCLUDE_DIRS += -I..
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR)
ADDITIONAL_OBJCFLAGS += -Wall

PREF_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/Bundles

include $(GNUSTEP_MAKEFILES)/bundle.make

.PHONY: custom-install custom-uninstall

install:: custom-install

custom-install: $(BUNDLE_NAME)$(BUNDLE_EXTENSION)
	$(MKDIRS) $(DESTDIR)$(PREF_INSTALL_DIR)
	cp -R $(BUNDLE_NAME)$(BUNDLE_EXTENSION) $(DESTDIR)$(PREF_INSTALL_DIR)/

uninstall:: custom-uninstall

custom-uninstall:
	rm -rf $(DESTDIR)$(PREF_INSTALL_DIR)/$(BUNDLE_NAME)$(BUNDLE_EXTENSION)

$(BUNDLE_NAME).install.bundle.variables::
	@true

shared-instance-bundle-install::
	@true

internal-bundle-install::
	@true
