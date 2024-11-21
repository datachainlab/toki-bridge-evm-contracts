SOURCES = $(wildcard ./src/*.sol)
FORGE_OBJECTS = $(patsubst %.sol,./out/%.sol/%.json,$(SOURCES))
HARDHAT_OBJECTS = $(patsubst %.sol,./artifacts/src/%.sol/%.json,$(SOURCES))
TYPECHAIN_DIR = script/tslib/typechain-types

.PHONY: help
help:
	echo "make <setup | build | build-hardhat | test | gas-report | slither | solhint >"

.PHONY: setup submodule
submodule:
	@if [ "x$(SKIP_SUBMODULE)" = "x1" ]; then \
	  echo "skip submodule"; \
	else \
	  echo "git submodule update --recursive --init"; \
	  git submodule update --recursive --init; \
	fi

setup: submodule
	npm install

.PHONY: build
build: $(FORGE_OBJECTS)

.PHONY: build-hardhat size-hardhat

build-hardhat:
	npm run build:hardhat

size-hardhat:
	npm run size

.PHONY: abi/merge_custom_errors.json
abi/merge_custom_errors.json: build-hardhat
	 npx ts-node ./script/tools/merge-custom-error-abis.ts > $@

.PHONY: typechain
typechain: $(TYPECHAIN_DIR) abi/merge_custom_errors.json
	npm run build:hardhat:typechain

$(TYPECHAIN_DIR):
	mkdir $@

$(FORGE_OBJECTS): $(SOURCES)
	npm run build

.PHONY: test
test:
	forge test -vvvv

.PHONY: test-ci
test-ci:
	FOUNDRY_PROFILE=ci forge test -vvvv

.PHONY: test-hardhat
test-hardhat:
	npm run test:hardhat

.PHONY: gas-report
gas-report:
	forge test --no-match-test "RevertsWhen|Fail" --gas-report

.PHONY: slither
slither:
	slither .

.PHONY: solhint
solhint:
	solhint 'src/**/*.sol'
	solhint -c test/.solhint.json 'test/**/*.sol'

.PHONY: network-hardhat
network-hardhat:
	npx hardhat node --port 8000

.PHONY: deploy
deploy:
	@# You need to set some environment variables. See main.ts
	npm run deploy

.PHONY: clean
clean:
	rm -rf out artifacts $(TYPECHAIN_DIR) cache cache_hardhat

.PHONY: clean-artifacts
clean-artifacts:
	rm -rf artifacts
