.PHONY: validate site
# Fetch the pinned compose-lint contract, then validate the catalog against it.
validate:
	bash scripts/fetch-contract.sh
	python .contract/validate_profiles.py --catalog-dir catalog --schema .contract/profile.schema.json --repo-root .

# Build the static catalog-browsing site (needs: pip install -r requirements-site.txt).
# Preview: python -m http.server -d _site
site:
	python scripts/build_site.py --out _site
