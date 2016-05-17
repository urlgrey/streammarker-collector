GO15VENDOREXPERIMENT=1

COVERAGEDIR = ./coverage
all: clean build test cover

clean: 
	if [ -d $(COVERAGEDIR) ]; then rm -rf $(COVERAGEDIR); fi
	if [ -e streammarker-collector ]; then rm -f streammarker-collector; fi

install-deps:
	glide install

all: build test

build:
	go build -v -o streammarker-collector

fmt:
	go fmt ./...

tc: test cover

test:
	if [ ! -d $(COVERAGEDIR) ]; then mkdir $(COVERAGEDIR); fi
	go test -v ./endpoint -race -cover -coverprofile=$(COVERAGEDIR)/endpoint.coverprofile

cover:
	go tool cover -html=$(COVERAGEDIR)/endpoint.coverprofile -o $(COVERAGEDIR)/endpoint.html

bench:
	go test ./... -cpu 2 -bench .

run: build
	$(CURDIR)/streammarker-collector

docker-build:
	docker info
	docker build -t skidder/streammarker-collector:latest .

docker-deploy:
	docker login -e ${DOCKER_EMAIL} -u ${DOCKER_USER} -p ${DOCKER_PASS}
	docker push skidder/streammarker-collector:latest
