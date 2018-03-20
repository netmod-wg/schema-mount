# In case your system doesn't have any of these tools:
# https://pypi.python.org/pypi/xml2rfc
# https://github.com/cabo/kramdown-rfc2629
# https://github.com/Juniper/libslax/tree/master/doc/oxtradoc
# https://tools.ietf.org/tools/idnits/

xml2rfc ?= xml2rfc
kramdown-rfc2629 ?= kramdown-rfc2629
oxtradoc ?= oxtradoc
idnits ?= idnits

draft := $(basename $(lastword $(sort $(wildcard draft-*.xml)) $(sort $(wildcard draft-*.md)) $(sort $(wildcard draft-*.org)) ))

ifeq (,$(draft))
$(warning No file named draft-*.md or draft-*.xml or draft-*.org)
$(error Read README.md for setup instructions)
endif

draft_type := $(suffix $(firstword $(wildcard $(draft).md $(draft).org $(draft).xml) ))

current_ver := $(shell git tag | grep '$(draft)-[0-9][0-9]' | tail -1 | sed -e"s/.*-//")
ifeq "${current_ver}" ""
next_ver ?= 00
else
next_ver ?= $(shell printf "%.2d" $$((1$(current_ver)-99)))
endif
next := $(draft)-$(next_ver)

examples = $(wildcard ex*.yang) \
	   $(wildcard *ex*.json) \
	   $(wildcard *ex*.xml)

.PHONY: latest all clean

all: $(next).txt

latest: $(draft).txt $(draft).html

back.xml: back.src.xml
	./mk-back $< > $@

ietf-yang-schema-mount.tree: ietf-yang-schema-mount.yang
	pyang -f tree --tree-line-length 68 $< > $@

idnits: $(next).txt
	$(idnits) $<

.PHONY: validate validate_ex1
validate:
	pyang --ietf --max-line-length 69 ietf-yang-schema-mount.yang
	pyang example-logical-devices.yang
	pyang example-network-manager-fixed.yang
	pyang example-network-manager-arbitrary.yang
	$(MAKE) validate_ex1
	$(MAKE) validate_yang_lib_ex1_device
	$(MAKE) validate_yang_lib_ex1_lne
	$(MAKE) validate_sm_ex1_lne
	$(MAKE) validate_sm_ex1_device

validate_ex1: .ex1.xml
	yang2dsdl -x -j -v $< ietf-yang-schema-mount.yang; \

.INTERMEDIATE: .ex1.xml
.ex1.xml: ex1.xml
	echo "<data xmlns='urn:ietf:params:xml:ns:netconf:base:1.0'>" > $@; \
	cat $< >> $@; \
	echo "</data>" >> $@

OLD_YANG_LIBRARY=${PYANG_XSLT_DIR}/../modules/ietf/ietf-yang-library.yang
NEW_YANG_LIBRARY=../../netconf-wg/rfc7895bis/ietf-yang-library.yang

.INTERMEDIATE: old-ietf-yang-library.jtox new-ietf-yang-library.jtox
old-ietf-yang-library.jtox:
	pyang -f jtox ${OLD_YANG_LIBRARY} > $@
new-ietf-yang-library.jtox:
	pyang --max-status current -f jtox ${NEW_YANG_LIBRARY} > $@

.INTERMEDIATE: .yang-library-ex1-device.xml .yang-library-ex1-lne.xml
.yang-library-ex1-device.xml: .yang-library-ex1-device.json \
	  new-ietf-yang-library.jtox
	json2xml new-ietf-yang-library.jtox $< > $@

.yang-library-ex1-lne.xml: .yang-library-ex1-lne.json \
	  old-ietf-yang-library.jtox
	json2xml old-ietf-yang-library.jtox $< > $@

validate_yang_lib_ex1_device: .yang-library-ex1-device.xml
	yang2dsdl -c -x -j -v $< ${NEW_YANG_LIBRARY}

validate_yang_lib_ex1_lne: .yang-library-ex1-lne.xml
	yang2dsdl -x -j -v $< ${OLD_YANG_LIBRARY}

.INTERMEDIATE: ietf-yang-schema-mount.jtox
ietf-yang-schema-mount.jtox: ietf-yang-schema-mount.yang
	pyang -f jtox $<  > $@

.INTERMEDIATE: .schema-mounts-ex1-device.xml .schema-mounts-ex1-lne.xml
.schema-mounts-ex1-%.xml: .schema-mounts-ex1-%.json \
	  ietf-yang-schema-mount.jtox
	json2xml ietf-yang-schema-mount.jtox $< > $@


validate_sm_ex1_lne: .schema-mounts-ex1-lne.xml
	yang2dsdl -x -j -v $< ietf-yang-schema-mount.yang

validate_sm_ex1_device: .schema-mounts-ex1-device.xml
	yang2dsdl -x -j -v $< ietf-yang-schema-mount.yang


.INTERMEDIATE: .%.json .%.json
.%.json: %.json
	cat $< | awk -F\\ '/(.*)\\/ { printf "%s", $$1; next } { print $$0 }' >\
	  $@

clean: clean_ex
	-rm -f ietf-yang-schema-mount.tree
	-rm -f $(draft).txt $(draft).html index.html back.xml
	-rm -f $(next).txt $(next).html
	-rm -f $(draft)-[0-9][0-9].xml
ifeq (.md,$(draft_type))
	-rm -f $(draft).xml
endif
ifeq (.org,$(draft_type))
	-rm -f $(draft).xml
endif

clean_ex:
	-rm -f *.rng *.dsrl *.sch

$(next).xml: ietf-yang-schema-mount.yang \
	ietf-yang-schema-mount.tree \
	back.xml $(examples)

$(next).xml: $(draft).xml
	sed -e"s/$(basename $<)-latest/$(basename $@)/" $< > $@

.INTERMEDIATE: $(draft).xml
%.xml: %.md
	$(kramdown-rfc2629) $< > $@

%.xml: %.org
	$(oxtradoc) -m outline-to-xml -n "$(basename $<)-latest" $< > $@

%.txt: %.xml
	$(xml2rfc) $< -o $@ --text

ifeq "$(shell uname -s 2>/dev/null)" "Darwin"
sed_i := sed -i ''
else
sed_i := sed -i
endif

%.html: %.xml
	$(xml2rfc) $< -o $@ --html
	$(sed_i) -f .addstyle.sed $@

### Below this deals with updating gh-pages

GHPAGES_TMP := /tmp/ghpages$(shell echo $$$$)
.TRANSIENT: $(GHPAGES_TMP)
ifeq (,$(TRAVIS_COMMIT))
GIT_ORIG := $(shell git branch | grep '*' | cut -c 3-)
else
GIT_ORIG := $(TRAVIS_COMMIT)
endif

# Only run upload if we are local or on the master branch
IS_LOCAL := $(if $(TRAVIS),,true)
ifeq (master,$(TRAVIS_BRANCH))
IS_MASTER := $(findstring false,$(TRAVIS_PULL_REQUEST))
else
IS_MASTER :=
endif

index.html: $(draft).html
	cp $< $@

ghpages: index.html $(draft).txt
ifneq (,$(or $(IS_LOCAL),$(IS_MASTER)))
	mkdir $(GHPAGES_TMP)
	cp -f $^ $(GHPAGES_TMP)
	git clean -qfdX
ifeq (true,$(TRAVIS))
	git config user.email "ci-bot@example.com"
	git config user.name "Travis CI Bot"
	git checkout -q --orphan gh-pages
	git rm -qr --cached .
	git clean -qfd
	git pull -qf origin gh-pages --depth=5
else
	git checkout gh-pages
	git pull
endif
	mv -f $(GHPAGES_TMP)/* $(CURDIR)
	git add $^
	if test `git status -s | wc -l` -gt 0; then git commit -m "Script updating gh-pages."; fi
ifneq (,$(GH_TOKEN))
	@echo git push https://github.com/$(TRAVIS_REPO_SLUG).git gh-pages
	@git push https://$(GH_TOKEN)@github.com/$(TRAVIS_REPO_SLUG).git gh-pages
endif
	-git checkout -qf "$(GIT_ORIG)"
	-rm -rf $(GHPAGES_TMP)
endif
