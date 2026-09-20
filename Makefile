.PHONY: init local-init validate test image serverless-image push start stop status local-up local-ui-up local-down local-logs warmup cli-test

IMAGE ?= qwen-runpod-helper:local

init:
	./scripts/init-pod-env.sh

local-init:
	./scripts/init-local-env.sh

validate:
	./scripts/validate-pod.sh

test: validate
	python3 -m unittest discover -s tests -v

image: validate
	docker build --platform linux/amd64 -t "$(IMAGE)" .

serverless-image: validate
	docker build --platform linux/amd64 -f Dockerfile.serverless -t "$(IMAGE)-serverless" .

push:
	docker push "$(IMAGE)"

start:
	./scripts/pod-control.sh start

stop:
	./scripts/pod-control.sh stop

status:
	./scripts/pod-control.sh status

local-up:
	docker compose --env-file local/compose.env --profile local-worker up --build -d

local-ui-up:
	docker compose --env-file local/compose.env up -d

local-down:
	docker compose --env-file local/compose.env down

local-logs:
	docker compose --env-file local/compose.env logs --follow

warmup:
	./scripts/test-openai-api.sh --wait

cli-test:
	./scripts/test-openai-api.sh
