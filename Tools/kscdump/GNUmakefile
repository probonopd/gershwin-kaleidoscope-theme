# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause

include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = kscdump
kscdump_OBJC_FILES = kscdump.m
ADDITIONAL_INCLUDE_DIRS += -I../..
ADDITIONAL_LIB_DIRS += -L../../$(GNUSTEP_OBJ_DIR)
ADDITIONAL_TOOL_LIBS += -lgnustep-gui -lKaleidoscopeScheme
ADDITIONAL_OBJCFLAGS += -Wall

include $(GNUSTEP_MAKEFILES)/tool.make
