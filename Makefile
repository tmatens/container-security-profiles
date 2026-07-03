.PHONY: validate
# Fetch the pinned compose-lint contract, then validate the catalog against it.
validate:
	bash scripts/fetch-contract.sh
	python .contract/validate_profiles.py --catalog-dir catalog --schema .contract/profile.schema.json --repo-root .
