.PHONY: init validate image push start stop status

IMAGE ?= qwen-runpod-helper:local

init:
	./scripts/init-pod-env.sh

validate:
	./scripts/validate-pod.sh

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
