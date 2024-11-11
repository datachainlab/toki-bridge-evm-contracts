NS := toki-contracts
WORKFLOW_FILES := pullreq.yaml push-main.yaml

help:
	@echo "make < submit | list | pod | log | delete-workflows >"

lint: $(WORKFLOW_FILES) $(PARAM_FILE)
	@for f in $(WORKFLOW_FILES); do \
	  echo $$f; \
	  argo lint $$f; \
	  yq $$f >/dev/null; \
	done

list:
	argo -n $(NS) list

pod:
	kubectl -n $(NS) get pod

get:
	argo -n $(NS) get $$(argo -n $(NS) list --running -o name | head -1)

log logs:
	argo -n $(NS) logs -f $$(argo -n $(NS) list --running -o name | head -1)

# To submit workflow by local cli for testing.
# Need to set SUBMIT env var and create parameter file with `param-$(SUBMIT)` filename.
#   `SUBMIT=pullreq.yaml make submit`
submit:
	@test ! -z $(SUBMIT) ||  { echo "set SUBMIT"; false; }
	@test -f $(SUBMIT) || { echo "no such file: $(SUBMIT)"; false; }
	@test -f param-$(SUBMIT) || { echo "no such file: param-$(SUBMIT)"; false; }
	argo submit -n $(NS) -f param-$(SUBMIT) $(SUBMIT)

logs-trigger:
	kubectl -n infra logs -f svc/infra-workflow-trigger-active

delete-workflows:
	argo -n $(NS) delete $$(argo -n $(NS) list -o name)

clean:
	rm *~

.PHONY: help submit lint list pod log logs delete clean

