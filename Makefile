# Makefile: builds the keyless (server) and testclient
#
# Copyright (c) 2013-2014 CloudFlare, Inc.

NAME := keyless

# This Makefile makes use of the GNU Make Standard Library project
# which can be found at http://gmsl.sf.net/

GMSL_DIR := gmsl/
include $(GMSL_DIR)/gmsl

include Version

TMP := tmp/

OS := $(shell uname -s)

# This is the SHA of the commit on Github of the libuv project that we will
# build against.

LIBUV_SHA := 1daff47ae9df55902f07d3c5b8a3a393306a2f1e

LIBUV_ROOT := $(TMP)libuv-$(LIBUV_SHA)
LIBUV_A := $(LIBUV_ROOT)/.libs/libuv.a
LIBUV_INCLUDE := $(LIBUV_ROOT)/include
LIBUV_LOG := $(TMP)libuv.log

# This is the version of OpenSSL to link against.

OPENSSL_VERSION := 1.0.1g

OPENSSL_ROOT := $(TMP)openssl-$(OPENSSL_VERSION)

# Note that the order libssl then libcrypto here is important otherwise the
# link will fail

OPENSSL_A := $(addprefix $(OPENSSL_ROOT)/,libssl.a libcrypto.a)
OPENSSL_INCLUDE := $(OPENSSL_ROOT)/include
OPENSSL_LOG := $(TMP)openssl.log

# Turn on absolutely all warnings and turn them into errors

CFLAGS += -g -Wall -Wextra -Wno-unused-parameter -Werror
CFLAGS += -I. -I$(LIBUV_INCLUDE) -I$(OPENSSL_INCLUDE)
CFLAGS += -DKSSL_VERSION=\"$(VERSION)-$(REVISION)\"

# Link against OpenSSL and libuv. libuv is built and linked against
# statically.
#
# Note that -ldl must appear after OPENSSL_A otherwise the link will fail

ifeq ($(OS),Linux)
LDLIBS := -lrt
else
LDLIBS :=
endif

LDLIBS += -lpthread -L. $(OPENSSL_A) $(LIBUV_A) -ldl

# Macros for automatically making directories using marker files.
# http://www.cmcrossroads.com/ask-mr-make/6936-making-directories-in-gnu-make
# for rationale.

marker = $1.f
make_dir = $(eval $1.f: ; @mkdir -p $$(dir $$@) ; touch $$@)

OBJ := o/
SERVER_OBJS := $(addprefix $(OBJ),keyless.o $(addprefix kssl_,helpers.o core.o private_key.o log.o thread.o getopt.o))
TEST_OBJS := $(addprefix $(OBJ),testclient.o $(addprefix kssl_,helpers.o log.o))
OBJS := $(SERVER_OBJS) $(TEST_OBJS)
EXECS := $(addprefix $(OBJ),keyless testclient)

.PHONY: all clean test run kill
all: libuv openssl $(OBJ) $(EXECS)
clean: ; @rm -rf $(OBJ) $(LIBUV_ROOT) $(LIBUV_ZIP) $(OPENSSL_ROOT) $(OPENSSL_TAR_GZ) $(DESTDIR)

$(call make_dir,$(TMP))

LIBUV_DIR := $(call marker,$(LIBUV_ROOT)/)

.PHONY: libuv
libuv: $(LIBUV_A)
$(LIBUV_A): $(call marker,$(TMP)) $(LIBUV_DIR)
	@cd $(LIBUV_ROOT) && ./autogen.sh && ./configure --enable-static && make

$(LIBUV_DIR): $(call marker,$(TMP))
	@rm -rf $(LIBUV_ROOT)
	@wget -qO $(TMP)$(LIBUV_SHA).zip http://github.com/joyent/libuv/archive/$(LIBUV_SHA).zip
	@unzip -d $(TMP) $(TMP)$(LIBUV_SHA).zip
	@touch $@

OPENSSL_DIR := $(call marker,$(OPENSSL_ROOT)/)

ifeq ($(OS),Darwin)
OPENSSL_CONFIG := Configure darwin64-x86_64-cc
else
OPENSSL_CONFIG := config
endif

.PHONY: openssl
openssl: $(firstword $(OPENSSL_A))

$(firstword $(OPENSSL_A)): $(OPENSSL_DIR)
	@cd $(OPENSSL_ROOT) && ./$(OPENSSL_CONFIG) no-shared && make

$(OPENSSL_DIR): $(call marker,$(TMP))
	@rm -rf $(OPENSSL_ROOT)
	@wget -qO $(TMP)openssl-$(OPENSSL_VERSION).tar.gz https://www.openssl.org/source/openssl-$(OPENSSL_VERSION).tar.gz
	@tar -C $(TMP) -z -x -v -f $(TMP)openssl-$(OPENSSL_VERSION).tar.gz
	@touch $@

PREFIX                  := usr/local
INSTALL_BIN             = $(DESTDIR)/$(PREFIX)/bin
INIT_DEFAULT_PREFIX     = $(DESTDIR)/etc/default
INIT_PREFIX             = $(DESTDIR)/etc/init.d
CONFIG_PREFIX           = $(DESTDIR)/etc/keyless

install-all: install install-config

install: all
	@mkdir -p $(INSTALL_BIN)
	@install -m755 o/$(NAME) $(INSTALL_BIN)

install-config:
	@mkdir -p $(CONFIG_PREFIX)
	@mkdir -p $(INIT_PREFIX)
	@mkdir -p $(INIT_DEFAULT_PREFIX)
	@install -m644 pkg/keyless.default $(INIT_DEFAULT_PREFIX)/keyless
	@install -m755 pkg/keyless.sysv $(INIT_PREFIX)/keyless
	@install -m644 pkg/keyless_cacert.pem $(CONFIG_PREFIX)/keyless_cacert.pem

VENDOR := "CloudFlare"
LICENSE := "See License File"
URL := "http://www.cloudflare.com"
DESCRIPTION="A reference implementation for CloudFlare's Keyless SSL server"

# Override DISTRO on the command-line to specify a particular distro
#
# e.g. make package DISTRO=debian

DISTRO := debian
ARCH := x86_64

DEB_PACKAGE := $(NAME)_$(VERSION)-$(ITERATION)_$(ARCH).deb
RPM_PACKAGE := $(NAME)-$(VERSION)_$(ITERATION).$(ARCH).rpm

# Include distro-specific settings

include Package-$(DISTRO)

FPM = fpm -C $(DESTDIR) \
	-n $(NAME) \
	-a $(ARCH) \
	-s dir \
	-t $(PACKAGE_TYPE) \
	-v $(VERSION) \
	--url $URL \
	--description $(DESCRIPTION) \
	--vendor $(VENDOR) \
	--license $(LICENSE) \
	--iteration $(ITERATION) \
	--before-install pkg/$(DISTRO)/before-install.sh \
	--before-remove  pkg/$(DISTRO)/before-remove.sh \
	--after-install  pkg/$(DISTRO)/after-install.sh \
	--config-files $(INIT_DEFAULT_PREFIX)/keyless \

$(DEB_PACKAGE):
	@$(FPM) \
	--deb-init=$(INIT_DEFAULT_PREFIX)/keyless \
	--deb-default=$(INIT_DEFAULT_PREFIX)/keyless \
	--deb-compression bzip2 \
	--deb-user root --deb-group root \
	.

$(RPM_PACKAGE):
	@$(FPM) \
	--rpm-use-file-permissions \
	--rpm-user root --rpm-group root \
	.

.PHONY: package
package: DESTDIR := build
package: clean all install-all $(PACKAGE)

.PHONY: cf-package
cf-package: DESTDIR := build
cf-package: DISTRO := debian
cf-package: clean all install $(PACKAGE)

.PHONY: clean-package
clean-package:
	@$(RM) -r $(DESTDIR)
	@$(RM) $(PACKAGE)

# Note the use of a # comment at the end of VALGRIND_COMMAND to ensure
# that there is a trailing space

VALGRIND_COMMAND :=
ifeq ($(VALGRIND),1)
VALGRIND_LOG := $(TMP)valgrind.log
VALGRIND_COMMAND := valgrind --leak-check=yes --log-file=$(VALGRIND_LOG) --show-reachable=yes --trace-children=yes #
endif

PORT := $(shell perl free-port.pl)
PID_FILE := $(TMP)$(NAME).pid
SERVER_LOG := $(TMP)$(NAME).log
CA_FILE := CA/cacert.pem
ifneq ($(wildcard $(PID_FILE)),)
PID := $(shell cat $(PID_FILE))
run: ; @echo $(NAME) running as PID $(PID)
kill:
	-@kill $(PID)
	@rm -f $(PID_FILE)
else
run: export LD_LIBRARY_PATH=/usr/local/lib
run: all $(call marker,$(TMP))
ifeq ($(VALGRIND),1)
	@rm -f $(VALGRIND_LOG)
endif
	@$(VALGRIND_COMMAND)$(OBJ)$(NAME) --port=$(PORT) --server-cert=server-cert/cert.pem --server-key=server-cert/key.pem --private-key-directory=keys --ca-file=$(CA_FILE) --pid-file=$(PID_FILE) --num-workers=4 --daemon --silent
ifeq ($(VALGRIND),1)
	@echo $$! > $(PID_FILE)
endif

kill: ;
endif

# Note that sub-makes are used here for the kill and run targets
# because the definition of those targets changes depending on the
# presence or absence of the $(NAME).pid file (see above) and thus
# it's necessary to restart make for them to do the right thing.

.PHONY: test-short
test-short: TEST_PARAMS := --short
test-short: test

test: export LD_LIBRARY_PATH=/usr/local/lib
test: all
	@$(MAKE) --no-print-directory kill
	@$(MAKE) --no-print-directory run VALGRIND=$(VALGRIND) PORT=$(PORT)
	@perl -e 'while (!-e "$(PID_FILE)") { sleep(1); }'
	@sleep 1
	@$(OBJ)testclient --port=$(PORT) --private-key=keys/private.key --client-cert=client-cert/cert.pem --client-key=client-cert/key.pem --ca-file=$(CA_FILE) $(DEBUG) --server=localhost $(TEST_PARAMS)
	@$(MAKE) --no-print-directory kill
ifeq ($(VALGRIND),1)
	@echo valgrind log in $(VALGRIND_LOG)
endif

$(OBJ):
	@mkdir -p $@

$(OBJ)$(NAME): $(SERVER_OBJS) ; @$(LINK.o) $^ $(LOADLIBES) $(LDLIBS) -o $@
$(OBJ)testclient: $(TEST_OBJS) ; @$(LINK.o) $^ $(LOADLIBES) $(LDLIBS) -o $@

$(OBJ)%.o: %.c ; @$(COMPILE.c) $(OUTPUT_OPTION) $<

$(OBJ)$(NAME).o: kssl.h
$(OBJ)testclient.o: kssl.h

include Release
