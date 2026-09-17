# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause

include $(GNUSTEP_MAKEFILES)/common.make

TEST_TOOL_NAME = t_KResourceFork t_KIconDecoder t_KScheme t_KSchemeStore t_KGarden

ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/TestFramework

t_KResourceFork_OBJC_FILES = t_KResourceFork.m
t_KIconDecoder_OBJC_FILES = t_KIconDecoder.m
t_KScheme_OBJC_FILES = t_KScheme.m
t_KSchemeStore_OBJC_FILES = t_KSchemeStore.m
t_KGarden_OBJC_FILES = t_KGarden.m

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/test-tool.make
