# really Basic Makefile for Skydive

PROTO_FILES=flow/flow.proto
VERBOSE_FLAGS?=-v
VERBOSE?=true
ifeq ($(VERBOSE), false)
	VERBOSE_FLAGS:=
endif
TIMEOUT?=1m
TEST_PATTERN?=
UT_PACKAGES=$(shell go list ./... | grep -v '/tests')
FUNC_TESTS_CMD:="grep -e 'func Test${TEST_PATTERN}' tests/*.go | perl -pe 's|.*func (.*?)\(.*|\1|g' | shuf"
FUNC_TESTS:=$(shell sh -c $(FUNC_TESTS_CMD))

.proto: godep builddep ${PROTO_FILES}
	protoc --go_out . ${PROTO_FILES}

.bindata: godep builddep
	go-bindata -nometadata -o statics/bindata.go -pkg=statics -ignore=bindata.go statics/*

all: genlocalfiles
	godep go install ${GOFLAGS} ${VERBOSE_FLAGS} ./...

install: godep
	godep go install ${GOFLAGS} ${VERBOSE_FLAGS} ./...

build: godep
	godep go build ${GOFLAGS} ${VERBOSE_FLAGS} ./...

test.functionals.cleanup:
	rm -f tests/functionals

test.functionals.compile: godep
	godep go test ${GOFLAGS} ${VERBOSE_FLAGS} -timeout ${TIMEOUT} -c -o tests/functionals ./tests/

test.functionals.run:
ifneq ($(VERBOSE_FLAGS),)
	cd tests && sudo -E ./functionals -test.v -test.timeout ${TIMEOUT} ${ARGS}
else
	cd tests && sudo -E ./functionals -test.timeout ${TIMEOUT} ${ARGS}
endif

test.functionals.all: test.functionals.compile
	make TIMEOUT="8m" ARGS=${ARGS} test.functionals.run

test.functionals: test.functionals.compile
	set -e ; \
	for functest in ${FUNC_TESTS} ; do \
		make ARGS="-test.run $$functest ${ARGS}" test.functionals.run ; \
	done

test: godep
	godep go test ${GOFLAGS} ${VERBOSE_FLAGS} -timeout ${TIMEOUT} ${UT_PACKAGES}

godep:
	go get github.com/tools/godep

fmt:
	@echo "+ $@"
	@test -z "$$(gofmt -s -l . | grep -v Godeps/_workspace/src/ | grep -v statics/bindata.go | tee /dev/stderr)" || \
		(echo "+ please format Go code with 'gofmt -s'" && /bin/false)

ineffassign interfacer golint goimports varcheck structcheck aligncheck deadcode gotype errcheck gocyclo dupl:
	@go get github.com/alecthomas/gometalinter
	@command -v $@ >/dev/null || gometalinter --install --update

gometalinter: ineffassign interfacer golint goimports varcheck structcheck aligncheck deadcode gotype errcheck gocyclo dupl

lint: gometalinter
	@echo "+ $@"
	@gometalinter --disable=gotype --skip=Godeps/... --skip=statics/... --deadline 5m --sort=path ./...  2>&1 | grep -v -e 'error return value not checked' -e 'should have comment or be unexported' -e 'declaration of err shadows declaration'

# dependency package need for building the project
builddep:
	go get github.com/golang/protobuf/proto
	go get github.com/golang/protobuf/protoc-gen-go
	go get github.com/jteeuwen/go-bindata/...

genlocalfiles: .proto .bindata

clean: test.functionals.cleanup
	grep ImportPath Godeps/Godeps.json | perl -pe 's|.*": "(.*?)".*|\1|g' | xargs -n 1 go clean -i >/dev/null 2>&1 || true
	rm -rf Godeps/_workspace/pkg

.PHONY: doc

doc:
	mkdir -p /tmp/skydive-doc
	hugo --theme=hugo-material-docs -s doc -d /tmp/skydive-doc
	git checkout gh-pages
	cp -dpR /tmp/skydive-doc/* .
	git add -A
	git commit -a -m "Documentation update"
	git push -f gerrit gh-pages

doctest:
	hugo server run -t hugo-material-docs -s doc -b http://localhost:1313/skydive
