# -- generic Makefile for building RPM-based packages out of source
#    code control systems (git, cvs, svn)

SCM_TYPE := git
SCM_PATH := ../../
#CVSROOT := $(shell cat 2>/dev/null src/CVS/Root)
#SVN_PATH := $(shell svn info ${SCM_PATH} 2>/dev/null | awk '/^URL:/{print $$2}')
#SVN_REV := $(shell svn info ${SVN_PATH} 2>/dev/null | awk '/^Last Changed Rev:/{print $$4}')

PACKAGE := $(shell cat PACKAGE)
VERSION := $(shell cat VERSION)
RELEASE := $(shell cat RELEASE)
BASE_VER := ${VERSION}-${RELEASE}
CURRENT_PACKAGE := $(PACKAGE)-$(BASE_VER)
TARBALL := $(CURRENT_PACKAGE).tar

DIRNAME := $(shell echo $${PWD})
DIRBASE := $(shell basename $${PWD})


.SUFFIXES:
.PHONY: clean mrclean distclean prepclean all default
.PHONY: rpm rpmdist buildrpm buildrpmdist
.PHONY: buildtarball buildtargz
.PHONY: builddir distdir prepbuildtarball
.PHONY: cvs-export git-export svn-export test-export
.PHONY: cvs-clean git-clean svn-clean test-clean
.PHONY: update

default: rpmdist

# -- the "rpmdist" target will build out of the SCM, but will
#    use the user's default build settings (which in many cases
#    is exposed as an RPM repository)
#
#rpmdist: buildrpmdist distclean
rpmdist: buildrpmdist

buildrpmdist: buildtargz
	@rpmbuild \
	  --define "_package ${PACKAGE}" \
	  --define "_version ${VERSION}" \
	  --define "_release ${RELEASE}" \
	  -ta ./build/$(TARBALL).gz

# -- the "srpmdist" target will build an SRPM out of the SCM, but
#    will use the user's default build settings (which in many
#    cases is exposed as an RPM repository)
#
srpmdist: buildsrpmdist

buildsrpmdist: buildtargz
	@rpmbuild \
	  --define "_package ${PACKAGE}" \
	  --define "_version ${VERSION}" \
	  --define "_release ${RELEASE}" \
	  -ts --nodeps ./build/$(TARBALL).gz

# -- the "rpm" target will build out of the SCM, but will leave
#    the resulting package in the relative ./build/ directory
#
rpm: buildrpm $(SCM_TYPE)-clean

buildrpm: buildtargz
	@echo ${PACKAGE} ${VERSION} ${RELEASE}
	@rpmbuild \
	  --define "_rpmdir ./build/" \
	  --define "_sourcedir ./build/" \
	  --define "_srcrpmdir ./build/" \
	  --define "_package ${PACKAGE}" \
	  --define "_version ${VERSION}" \
	  --define "_release ${RELEASE}" \
	  -ta ./build/$(TARBALL).gz

# -- the "srpm" target will build an SRPM out of the SCM, but
#    will leave the resulting package in the relative ./build/
#    directory
#
srpm: buildsrpm $(SCM_TYPE)-clean

buildsrpm: buildtargz
	@echo ${PACKAGE} ${VERSION} ${RELEASE}
	@rpmbuild \
	  --define "_rpmdir ./build/" \
	  --define "_sourcedir ./build/" \
	  --define "_srcrpmdir ./build/" \
	  --define "_package ${PACKAGE}" \
	  --define "_version ${VERSION}" \
	  --define "_release ${RELEASE}" \
	  -ts --nodeps ./build/$(TARBALL).gz

buildtarball: prepbuildtarball
	@tar \
	  --create \
	  --directory ./build/ \
	  --file      ./build/$(TARBALL) \
	  ${CURRENT_PACKAGE}

buildtargz: buildtarball
	@gzip -c < ./build/$(TARBALL) > ./build/$(TARBALL).gz

prepbuildtarball: $(SCM_TYPE)-export
	${MAKE} update \
	  && cp ${PACKAGE}.spec ./build/${CURRENT_PACKAGE} \
	  && cp files/* ./build/

test-clean:
	@cd .. \
	  && rm "$(CURRENT_PACKAGE)"

test-export: builddir
	@cd .. \
	  && ln -snvf $(DIRBASE) $(CURRENT_PACKAGE) \
	  && tar \
	    --create \
	    --dereference \
	    --to-stdout \
	    --exclude "*.git*" \
	    --exclude "*.svn*" \
	    --exclude "*/CVS/*" \
	    --exclude "$(CURRENT_PACKAGE)/build/*" \
	      $(CURRENT_PACKAGE) \
	  | tar \
	    --extract \
	    --directory $(CURRENT_PACKAGE)/build/ \
	    --file -

git-export: builddir prepclean
	(cd $(SCM_PATH) ; git archive --format=tar --prefix=$(CURRENT_PACKAGE)/ HEAD) \
	  | tar \
	    --extract \
	    --directory ./build/ \
	    --file -

git-clean:
	@:

cvs-export: builddir prepclean
	@cd ./build/ \
	  && echo CURRENT_PACKAGE: ${CURRENT_PACKAGE} \
	  && echo CVSROOT: ${CVSROOT} \
	  && CVSROOT=${CVSROOT} cvs export -r HEAD -d$(CURRENT_PACKAGE) ${PACKAGE}

cvs-clean:
	@:

svn-export: builddir prepclean
	@cd ./build/ \
	  && svn export $(SVN_PATH) $(CURRENT_PACKAGE)

svn-clean:
	@:

builddir:
	@mkdir -p ./build

distdir:
	@mkdir -p ./dist

prepclean:
	@rm -rf ./build/$(CURRENT_PACKAGE)*

clean:
	@rm -rf ./build/* ./dist/* ${PACKAGE}.spec 2>/dev/null || :

mrclean: clean

distclean: clean $(SCM_TYPE)-clean
	@rmdir ./build/ ./dist/ 2>/dev/null || :

# -- recursive Makefile calls (during build phase)
#
update: $(PACKAGE).spec VERSION RELEASE

$(PACKAGE).spec: VERSION RELEASE $(PACKAGE).spec.in
	@sed \
	  -e "s|@PACKAGE@|$(PACKAGE)|" \
	  -e "s|@VERSION@|$(VERSION)|" \
	  -e "s|@RELEASE@|$(RELEASE)|" \
	  < $(PACKAGE).spec.in > $@

# -- end of Makefile
