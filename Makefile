.PHONY: check test verify all

all: check test verify

check:
	@find . \( -name '*.sh' -o -path './bin/dotlink' \) -not -path './.git/*' -print0 | sort -z | xargs -0 -n1 bash -n --
	@echo "shell syntax checks passed"

test:
	@dotlink/tests/run.sh

verify:
	@scripts/verify-bootstrap-split.sh
