INST_PREFIX ?= /usr
INST_LIBDIR ?= $(INST_PREFIX)/lib64/lua/5.1
INST_LUADIR ?= $(INST_PREFIX)/share/lua/5.1
INST_BINDIR ?= /usr/bin
INSTALL ?= install
UNAME ?= $(shell uname)
UNAME_MACHINE ?= $(shell uname -m)
OR_EXEC ?= $(shell which openresty || which nginx)
LUAROCKS ?= luarocks
LUAROCKS_VER ?= $(shell luarocks --version | grep -E -o  "luarocks [0-9]+.")
OR_PREFIX ?= $(shell $(OR_EXEC) -V 2>&1 | grep -Eo 'prefix=(.*)/nginx\s+' | grep -Eo '/.*/')
OPENSSL_PREFIX ?= $(addprefix $(OR_PREFIX), openssl)
HOMEBREW_PREFIX ?= /usr/local

show:
	@echo ${INST_PREFIX}
	@echo ${INST_LIBDIR}
	@echo ${INST_LUADIR}
	@echo ${INST_BINDIR}
	@echo ${INSTALL}
	@echo ${UNAME}
	@echo ${UNAME_MACHINE}
	@echo ${OR_EXEC}
	@echo ${LUAROCKS}
	@echo ${LUAROCKS_VER}
	@echo ${OR_PREFIX}
	@echo ${OPENSSL_PREFIX}
	@echo ${HOMEBREW_PREFIX}

# OpenResty 1.17.8 or higher version uses openssl111 as the openssl dirname.
ifeq ($(shell test -d $(addprefix $(OR_PREFIX), openssl111) && echo -n yes), yes)
	OPENSSL_PREFIX=$(addprefix $(OR_PREFIX), openssl111)
endif

ifeq ($(UNAME), Darwin)
	ifeq ($(UNAME_MACHINE), arm64)
		HOMEBREW_PREFIX=/opt/homebrew
	endif
	LUAROCKS=luarocks --lua-dir=$(HOMEBREW_PREFIX)/opt/lua@5.1
	ifeq ($(shell test -d $(HOMEBREW_PREFIX)/opt/openresty-openssl && echo yes), yes)
		OPENSSL_PREFIX=$(HOMEBREW_PREFIX)/opt/openresty-openssl
	endif
	ifeq ($(shell test -d $(HOMEBREW_PREFIX)/opt/openresty-openssl111 && echo yes), yes)
		OPENSSL_PREFIX=$(HOMEBREW_PREFIX)/opt/openresty-openssl111
	endif
endif

LUAROCKS_SERVER_OPT =
ifneq ($(LUAROCKS_SERVER), )
	LUAROCKS_SERVER_OPT = --server ${LUAROCKS_SERVER}
endif

SHELL := /bin/bash -o pipefail

VERSION ?= latest
RELEASE_SRC = ztgw-${VERSION}-src

.PHONY: default
default:
ifeq ($(OR_EXEC), )
	ifeq ("$(wildcard /usr/local/openresty-debug/bin/openresty)", "")
		@echo "WARNING: OpenResty not found. You have to install OpenResty and add the binary file to PATH before install ztgw."
		exit 1
	else
		OR_EXEC=/usr/local/openresty-debug/bin/openresty
		@echo "deafult"
		@echo ${OR_EXEC}
	endif
endif

LUAJIT_DIR ?= $(shell ${OR_EXEC} -V 2>&1 | grep prefix | grep -Eo 'prefix=(.*)/nginx\s+--' | grep -Eo '/.*/')luajit

### help:             Show Makefile rules
.PHONY: help
help: default
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'


### deps:             Installation dependencies
.PHONY: deps
deps: default
ifeq ($(LUAROCKS_VER),luarocks 3.)
	mkdir -p ~/.luarocks
ifeq ($(shell whoami),root)
	$(LUAROCKS) config variables.OPENSSL_LIBDIR $(addprefix $(OPENSSL_PREFIX), /lib)
	$(LUAROCKS) config variables.OPENSSL_INCDIR $(addprefix $(OPENSSL_PREFIX), /include)
else
	$(LUAROCKS) config --local variables.OPENSSL_LIBDIR $(addprefix $(OPENSSL_PREFIX), /lib)
	$(LUAROCKS) config --local variables.OPENSSL_INCDIR $(addprefix $(OPENSSL_PREFIX), /include)
endif
	$(LUAROCKS) install rockspec/ztgw-0.1-0.rockspec --tree=deps --only-deps --local $(LUAROCKS_SERVER_OPT)
else
	@echo "WARN: You're not using LuaRocks 3.x, please add the following items to your LuaRocks config file:"
	@echo "variables = {"
	@echo "    OPENSSL_LIBDIR=$(addprefix $(OPENSSL_PREFIX), /lib)"
	@echo "    OPENSSL_INCDIR=$(addprefix $(OPENSSL_PREFIX), /include)"
	@echo "}"
	luarocks install rockspec/ztgw-0.1-0.rockspec --tree=deps --only-deps --local $(LUAROCKS_SERVER_OPT)
endif

### init:             Initialize the runtime environment
.PHONY: init
init: default
	./bin/ztgw init

### start:              Start the ztgw server
.PHONY: start
start: default
	./bin/ztgw start


### restart:             Restart the ztgw server, exit gracefully
.PHONY: restart
quit: default
	./bin/ztgw restart


### stop:             Stop the ztgw server, exit immediately
.PHONY: stop
stop: default
	./bin/ztgw stop


### verify:           Verify the configuration of ztgw server
.PHONY: verify
verify: default
	$(OR_EXEC) -p $$PWD/ -c $$PWD/conf/nginx.conf -t


### clean:            Remove generated files
.PHONY: clean
clean:
	@echo "clean rm -rf logs"
	rm -rf logs/


### reload:           Reload the ztgw server
.PHONY: reload
reload: default
	$(OR_EXEC) -p $$PWD/  -c $$PWD/conf/nginx.conf -s reload


### install:          Install the ztgw (only for luarocks)
.PHONY: install
install: default
	$(INSTALL) -d /usr/local/ztgw/
	$(INSTALL) -d /usr/local/ztgw/logs/
	$(INSTALL) -d /usr/local/ztgw/etc/
	$(INSTALL) -d /usr/local/ztgw/conf/cert
	$(INSTALL) conf/nginx.conf /usr/local/ztgw/conf/nginx.conf
	$(INSTALL) conf/mime.types /usr/local/ztgw/conf/mime.types
	$(INSTALL) etc/config.yaml /usr/local/ztgw/etc/config.yaml
	$(INSTALL) conf/cert/* /usr/local/ztgw/conf/cert/

	$(INSTALL) -d $(INST_LUADIR)/ztgw
	$(INSTALL) ztgw/*.lua $(INST_LUADIR)/ztgw/


	$(INSTALL) -d $(INST_LUADIR)/ztgw/core
	$(INSTALL) ztgw/core/*.lua $(INST_LUADIR)/ztgw/core/

	$(INSTALL) -d $(INST_LUADIR)/ztgw/cli
	$(INSTALL) ztgw/cli/*.lua $(INST_LUADIR)/ztgw/cli/
	$(INSTALL) -d $(INST_LUADIR)/ztgw/utils
	$(INSTALL) ztgw/utils/*.lua $(INST_LUADIR)/ztgw/utils/

	$(INSTALL) bin/ztgw $(INST_BINDIR)/ztgw
