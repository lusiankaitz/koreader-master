# koreader-base directory
KOR_BASE?=base

# the repository might not have been checked out yet, so make this
# able to fail:
-include $(KOR_BASE)/Makefile.defs

# we want VERSION to carry the version of koreader, not koreader-base
VERSION=$(shell git describe HEAD)
REVISION=$(shell git rev-parse --short HEAD)

# set PATH to find CC in managed toolchains
ifeq ($(TARGET), android)
	PATH:=$(CURDIR)/$(KOR_BASE)/$(ANDROID_TOOLCHAIN)/bin:$(PATH)
else ifeq ($(TARGET), pocketbook)
	PATH:=$(CURDIR)/$(KOR_BASE)/$(POCKETBOOK_TOOLCHAIN)/bin:$(PATH)
endif

MACHINE?=$(shell PATH=$(PATH) $(CC) -dumpmachine 2>/dev/null)
INSTALL_DIR=koreader-$(MACHINE)

# platform directories
PLATFORM_DIR=platform
KINDLE_DIR=$(PLATFORM_DIR)/kindle
KOBO_DIR=$(PLATFORM_DIR)/kobo
POCKETBOOK_DIR=$(PLATFORM_DIR)/pocketbook
ANDROID_DIR=$(PLATFORM_DIR)/android
ANDROID_LAUNCHER_DIR:=$(ANDROID_DIR)/luajit-launcher
WIN32_DIR=$(PLATFORM_DIR)/win32

# files to link from main directory
INSTALL_FILES=reader.lua frontend resources defaults.lua l10n \
		git-rev README.md COPYING

# for gettext
DOMAIN=koreader
TEMPLATE_DIR=l10n/templates
KOREADER_MISC_TOOL=../misc
XGETTEXT_BIN=$(KOREADER_MISC_TOOL)/gettext/lua_xgettext.py


all: $(if $(ANDROID),,$(KOR_BASE)/$(OUTPUT_DIR)/luajit)
	$(MAKE) -C $(KOR_BASE)
	echo $(VERSION) > git-rev
	mkdir -p $(INSTALL_DIR)/koreader
ifneq ($(or $(EMULATE_READER),$(WIN32)),)
	cp -f $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/koreader/
	# create symlink instead of copying files in development mode
	cd $(INSTALL_DIR)/koreader && \
		ln -sf ../../$(KOR_BASE)/$(OUTPUT_DIR)/* .
	# install front spec only for the emulator
	cd $(INSTALL_DIR)/koreader/spec && test -e front || \
		ln -sf ../../../../spec ./front
	cd $(INSTALL_DIR)/koreader/spec/front/unit && test -e data || \
		ln -sf ../../test ./data
else
	cp -rfL $(KOR_BASE)/$(OUTPUT_DIR)/* $(INSTALL_DIR)/koreader/
endif
	for f in $(INSTALL_FILES); do \
		ln -sf ../../$$f $(INSTALL_DIR)/koreader/; \
	done
ifdef ANDROID
	cd $(INSTALL_DIR)/koreader && \
		ln -sf ../../$(ANDROID_DIR)/*.lua .
endif
ifdef WIN32
	# install runtime libraries for win32
	cd $(INSTALL_DIR)/koreader && cp ../../$(WIN32_DIR)/*.dll .
endif
	# install plugins
	cp -r plugins/* $(INSTALL_DIR)/koreader/plugins/
	cp -rpL resources/fonts/* $(INSTALL_DIR)/koreader/fonts/
	mkdir -p $(INSTALL_DIR)/koreader/screenshots
	mkdir -p $(INSTALL_DIR)/koreader/data/dict
	mkdir -p $(INSTALL_DIR)/koreader/data/tessdata
	mkdir -p $(INSTALL_DIR)/koreader/fonts/host
	mkdir -p $(INSTALL_DIR)/koreader/ota
ifeq ($(or $(EMULATE_READER),$(WIN32)),)
	# clean up, remove unused files for releases
	rm -rf $(INSTALL_DIR)/koreader/data/{cr3.ini,cr3skin-format.txt,desktop,devices,manual}
	rm $(INSTALL_DIR)/koreader/fonts/droid/DroidSansFallbackFull.ttc
endif

$(KOR_BASE)/$(OUTPUT_DIR)/luajit:
	$(MAKE) -C $(KOR_BASE)

$(INSTALL_DIR)/koreader/.busted:
	test -e $(INSTALL_DIR)/koreader/.busted || \
		ln -sf ../../.busted $(INSTALL_DIR)/koreader

$(INSTALL_DIR)/koreader/.luacov:
	test -e $(INSTALL_DIR)/koreader/.luacov || \
		ln -sf ../../.luacov $(INSTALL_DIR)/koreader

testfront: $(INSTALL_DIR)/koreader/.busted
	cd $(INSTALL_DIR)/koreader && busted -l ./luajit

test:
	$(MAKE) -C $(KOR_BASE) test
	$(MAKE) testfront

coverage: $(INSTALL_DIR)/koreader/.luacov
	cd $(INSTALL_DIR)/koreader && busted -c -l ./luajit --exclude-tags=nocov
	# coverage report summary
	cd $(INSTALL_DIR)/koreader && tail -n \
		+$$(($$(grep -nm1 Summary luacov.report.out|cut -d: -f1)-1)) \
		luacov.report.out

fetchthirdparty:
	git submodule init
	git submodule sync
	git submodule update
	$(MAKE) -C $(KOR_BASE) fetchthirdparty

VERBOSE ?= @
Q = $(VERBOSE:1=)
clean:
	rm -rf $(INSTALL_DIR)
	$(Q:@=@echo 'MAKE -C base clean'; &> /dev/null) \
		$(MAKE) -C $(KOR_BASE) clean

# Don't bundle launchpad on touch devices..
ifeq ($(TARGET), kindle-legacy)
KINDLE_LEGACY_LAUNCHER:=launchpad
endif
kindleupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-kindle-$(MACHINE)-$(VERSION).zip
	# Kindle launching scripts
	ln -sf ../$(KINDLE_DIR)/extensions $(INSTALL_DIR)/
	ln -sf ../$(KINDLE_DIR)/launchpad $(INSTALL_DIR)/
	ln -sf ../../$(KINDLE_DIR)/koreader.sh $(INSTALL_DIR)/koreader
	ln -sf ../../$(KINDLE_DIR)/libkohelper.sh $(INSTALL_DIR)/koreader
	ln -sf ../../$(KINDLE_DIR)/kotar_cpoint $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && pwd && \
		zip -9 -r \
			../koreader-kindle-$(MACHINE)-$(VERSION).zip \
			extensions koreader $(KINDLE_LEGACY_LAUNCHER) \
			-x "koreader/resources/fonts/*" "koreader/ota/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*"
	# generate kindleupdate package index file
	zipinfo -1 koreader-kindle-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-kindle-$(MACHINE)-$(VERSION).zip \
		koreader/ota/package.index
	# make gzip kindleupdate for zsync OTA update
	cd $(INSTALL_DIR) && \
		tar czafh ../koreader-kindle-$(MACHINE)-$(VERSION).tar.gz \
		-T koreader/ota/package.index --no-recursion

koboupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-kobo-$(MACHINE)-$(VERSION).zip
	# Kobo launching scripts
	mkdir -p $(INSTALL_DIR)/kobo/mnt/onboard/.kobo
	ln -sf ../../../../../$(KOBO_DIR)/fmon $(INSTALL_DIR)/kobo/mnt/onboard/.kobo/
	cd $(INSTALL_DIR)/kobo && tar -czhf ../KoboRoot.tgz mnt
	cp resources/koreader.png $(INSTALL_DIR)/koreader.png
	cp $(KOBO_DIR)/fmon/README.txt $(INSTALL_DIR)/README_kobo.txt
	cp $(KOBO_DIR)/koreader.sh $(INSTALL_DIR)/koreader
	cp $(KOBO_DIR)/suspend.sh $(INSTALL_DIR)/koreader
	cp $(KOBO_DIR)/nickel.sh $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-kobo-$(MACHINE)-$(VERSION).zip \
			koreader -x "koreader/resources/fonts/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*"
	# generate koboupdate package index file
	zipinfo -1 koreader-kobo-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-kobo-$(MACHINE)-$(VERSION).zip \
		koreader/ota/package.index KoboRoot.tgz koreader.png README_kobo.txt
	# make gzip koboupdate for zsync OTA update
	cd $(INSTALL_DIR) && \
		tar czafh ../koreader-kobo-$(MACHINE)-$(VERSION).tar.gz \
		-T koreader/ota/package.index --no-recursion

pbupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-pocketbook-$(MACHINE)-$(VERSION).zip
	# Pocketbook launching script
	mkdir -p $(INSTALL_DIR)/applications
	mkdir -p $(INSTALL_DIR)/system/bin
	mkdir -p $(INSTALL_DIR)/system/config

	cp $(POCKETBOOK_DIR)/koreader.app $(INSTALL_DIR)/applications
	cp $(POCKETBOOK_DIR)/koreader.app $(INSTALL_DIR)/system/bin
	cp $(POCKETBOOK_DIR)/extensions.cfg $(INSTALL_DIR)/system/config
	cp -rfL $(INSTALL_DIR)/koreader $(INSTALL_DIR)/applications
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-pocketbook-$(MACHINE)-$(VERSION).zip \
			applications -x "applications/koreader/resources/fonts/*" \
			"applications/koreader/resources/icons/src/*" "applications/koreader/spec/*"
	# generate koboupdate package index file
	zipinfo -1 koreader-pocketbook-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	echo "applications/koreader/ota/package.index" >> \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	# hack file path when running tar in parent directory of koreader
	sed -i -e 's/^/..\//' \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -ru ../koreader-pocketbook-$(MACHINE)-$(VERSION).zip \
		applications/koreader/ota/package.index system
	# make gzip pbupdate for zsync OTA update
	cd $(INSTALL_DIR)/applications && \
		tar czafh ../../koreader-pocketbook-$(MACHINE)-$(VERSION).tar.gz \
		-T koreader/ota/package.index --no-recursion

androidupdate: all
	mkdir -p $(ANDROID_LAUNCHER_DIR)/assets/module
	-rm $(ANDROID_LAUNCHER_DIR)/assets/module/koreader-*
	cd $(INSTALL_DIR)/koreader && 7z a -l -mx=1 \
		../../$(ANDROID_LAUNCHER_DIR)/assets/module/koreader-g$(REVISION).7z * \
		-x!resources/fonts -x!resources/icons/src -x!spec
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) apk
	cp $(ANDROID_LAUNCHER_DIR)/bin/NativeActivity-debug.apk \
		koreader-android-$(MACHINE)-$(VERSION).apk

androiddev: androidupdate
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) dev

android-toolchain:
	$(MAKE) -C $(KOR_BASE) android-toolchain

pocketbook-toolchain:
	$(MAKE) -C $(KOR_BASE) pocketbook-toolchain

pot:
	mkdir -p $(TEMPLATE_DIR)
	$(XGETTEXT_BIN) reader.lua `find frontend -iname "*.lua"` \
		`find plugins -iname "*.lua"` \
		> $(TEMPLATE_DIR)/$(DOMAIN).pot
	# push source file to Transifex
	$(MAKE) -i -C l10n bootstrap push

po:
	$(MAKE) -i -C l10n bootstrap pull

.PHONY: test
