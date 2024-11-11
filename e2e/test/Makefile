NPM_TARGETS = \
	testSendCredit \
  testTransferToken \
  testTransferTokenFailCap \
  testTransferPool \
  testWithdrawInstant \
  testWithdrawRemote \
  testWithdrawLocal \
  testOuterServiceSuccess \
	testOuterServiceFailGas \
	testOuterServiceFailRevert \
  testOuterCallSuccess \
  testOuterCallFailRevert \
  testOuterCallFailBridgeGas \
  testMulticall \
  testError \
	deposit \
	show \

NPM_TARGETS_UPGRADE = \
	testUpgradePoolToV1 \
	testUpgradePoolV1ToV2Fail \

.PHONY: help
help:
	@echo "targets are: "; for t in $(NPM_TARGETS) $(NPM_TARGETS_UPGRADE); do echo "  $$t"; done

.PHONY: setup
setup:
	cd ../../script/tslib; npm ci
	npm ci

.PHONY: test
test:
	npm test

.PHONY: citest
citest:
	$(MAKE) show
	$(MAKE) testUpgradePoolToV1
	$(MAKE) testUpgradePoolV1ToV2Fail
	$(MAKE) testMulticall
	$(MAKE) testSendCredit
	$(MAKE) testTransferToken
	$(MAKE) testTransferTokenFailCap
	$(MAKE) testTransferPool
	$(MAKE) testWithdrawInstant
	$(MAKE) testWithdrawRemote
	$(MAKE) testWithdrawLocal
	$(MAKE) testOuterServiceSuccess
	$(MAKE) testOuterServiceFailGas
	$(MAKE) testOuterServiceFailRevert
	$(MAKE) testOuterCallSuccess
	$(MAKE) testOuterCallFailRevert
	$(MAKE) testOuterCallFailBridgeGas


.PHONY: all
all:
	@# upgrade pool to v1
	npm run testUpgradePoolToV1
	@# secondly, upgrade pool from v1 to v2(failed)
	npm run testUpgradePoolV1ToV2Fail
	@# and test with MockUpgradePool
	npm test

.PHONY: $(NPM_TARGETS) $(NPM_TARGETS_UPGRADE)
$(NPM_TARGETS):
	npm run $@

$(NPM_TARGETS_UPGRADE):
	rm -rf ../../.openzeppelin/*.json
	npm run $@
