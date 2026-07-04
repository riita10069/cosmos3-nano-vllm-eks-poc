SHELL := /usr/bin/env bash

AWS_REGION ?= us-east-1
CLUSTER_NAME ?= cosmos3-vllm-poc

.PHONY: check tf-init tf-apply kubeconfig device-plugin hf-secret deploy wait port-forward invoke-text invoke-image invoke-video clean-k8s tf-destroy

check:
	./scripts/00-check-prereqs.sh

tf-init:
	cd terraform && terraform init

tf-apply:
	cd terraform && terraform apply

kubeconfig:
	AWS_REGION=$(AWS_REGION) CLUSTER_NAME=$(CLUSTER_NAME) ./scripts/01-update-kubeconfig.sh

device-plugin:
	./scripts/02-install-device-plugin.sh

hf-secret:
	./scripts/03-create-hf-secret.sh

deploy:
	./scripts/04-deploy-cosmos-vllm.sh

wait:
	./scripts/05-wait-cosmos-vllm.sh

port-forward:
	./scripts/06-port-forward.sh

invoke-text:
	./scripts/07-invoke-text.sh

invoke-image:
	./scripts/08-invoke-image.sh

invoke-video:
	./scripts/09-invoke-video.sh

clean-k8s:
	./scripts/10-clean-k8s.sh

tf-destroy:
	cd terraform && terraform destroy
