.PHONY: help install data validate test bicep deploy-infra deploy-sql

RG       ?= rg-claims-dev
LOCATION ?= westeurope

help:  ## Show available targets
	@grep -E "^[a-z-]+:.*##" $(MAKEFILE_LIST) | awk -F ":.*## " '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

install:  ## Install dev dependencies
	pip install -e ".[dev]"

data:  ## Regenerate synthetic source extracts + partner file
	python scripts/generate_sample_data.py

validate:  ## Static validation of every ADF artifact
	python scripts/validate_adf.py

test:  ## ADF artifact tests + T-SQL parse tests
	pytest

bicep:  ## Compile + lint the Bicep templates
	az bicep build --file infra/bicep/main.bicep --stdout > /dev/null && az bicep lint --file infra/bicep/main.bicep

deploy-infra:  ## Deploy storage, ADF, Synapse, Key Vault (prompts for SQL password)
	az group create -n $(RG) -l $(LOCATION)
	az deployment group create -g $(RG) -f infra/bicep/main.bicep -p infra/bicep/main.parameters.json

deploy-sql:  ## Create Synapse objects (needs sqlcmd + AAD login)
	for f in synapse/sql/0*.sql synapse/sql/procedures/*.sql; do \
	  sqlcmd -S $$SYNAPSE_SQL_ENDPOINT -d claimsdw -G -i $$f || exit 1; done
