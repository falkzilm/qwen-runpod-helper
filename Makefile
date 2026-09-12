.PHONY: init validate test image push start stop status

IMAGE ?= qwen-runpod-helper:local

init:
	./scripts/init-pod-env.sh

validate:
	./scripts/validate-pod.sh

test: validate
	python3 -m unittest discover -s tests -v

image: validate
	docker build --platform linux/amd64 -t "$(IMAGE)" .

push:
	docker push "$(IMAGE)"

start:
	./scripts/pod-control.sh start

stop:
	./scripts/pod-control.sh stop

status:
	./scripts/pod-control.sh status
