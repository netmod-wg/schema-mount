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

PYANGFLAGS ?= -p ../../netconf-wg/rfc7895bis -p ../datastore-dt

.PHONY: latest all clean

all: $(next).txt

latest: $(draft).txt $(draft).html

back.xml: back.src.xml
	./mk-back $< > $@

ietf-yang-schema-mount.tree: ietf-yang-schema-mount.yang
	pyang $(PYANGFLAGS) -f tree --tree-line-length 68 $< > $@

idnits: $(next).txt
	$(idnits) $<

.PHONY: validate
validate:
	pyang $(PYANGFLAGS) --ietf --max-line-length 69 \
		ietf-yang-schema-mount.yang
	pyang $(PYANGFLAGS) example-logical-devices.yang
	pyang $(PYANGFLAGS) example-network-manager-fixed.yang
	pyang $(PYANGFLAGS) example-network-manager-arbitrary.yang

clean:
	-rm -f ietf-yang-schema-mount.tree
	-rm -f $(draft).txt $(draft).html index.html back.xml
	-rm -f $(next).txt $(next).html
	-rm -f $(draft)-[0-9][0-9].xml
	-rm -f *.rng *.dsrl *.sch
ifeq (.md,$(draft_type))
	-rm -f $(draft).xml
endif
ifeq (.org,$(draft_type))
	-rm -f $(draft).xml
endif

$(next).xml: ietf-yang-schema-mount.yang \
	ietf-yang-schema-mount.tree \
	example-logical-devices.yang \
	example-network-manager-fixed.yang \
	example-network-manager-arbitrary.yang \
	yang-library-ex1-device.json \
	schema-mounts-ex1-device.json \
	config-ex1-device.json \
	yang-library-ex1-lne.json \
	interfaces-ex1-lne.json \
	schema-mounts-ex1-lne.json \
	back.xml

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
